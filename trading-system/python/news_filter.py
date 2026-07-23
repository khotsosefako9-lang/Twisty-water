"""
Economic news blackout filter. Pulls the ForexFactory weekly calendar JSON
feed (no API key required) and blocks entries within a configurable window
around high-impact events for the currencies relevant to a symbol.

This is the equivalent of NewsFilter.mqh's CSV fallback path — the MT5 EA
prefers the terminal's native Economic Calendar API, but the Python bridge
has no such built-in, so it goes straight to a calendar feed.
"""
from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional

import requests

from config import NewsConfig

log = logging.getLogger("news_filter")


@dataclass
class NewsEvent:
    title: str
    country: str
    date: datetime
    impact: str  # "High", "Medium", "Low"


class NewsFilter:
    def __init__(self, config: NewsConfig):
        self.config = config
        self._cache: list[NewsEvent] = []
        self._cache_time: float = 0.0

    def _symbol_currencies(self, symbol: str) -> list[str]:
        if len(symbol) >= 6:
            return [symbol[:3].upper(), symbol[3:6].upper()]
        return ["USD"]

    def _refresh_cache(self) -> None:
        now = time.time()
        if self._cache and (now - self._cache_time) < self.config.cache_ttl_seconds:
            return

        try:
            resp = requests.get(self.config.forexfactory_json_url, timeout=10)
            resp.raise_for_status()
            raw_events = resp.json()
        except Exception as exc:  # network/parse failure must never crash the trading loop
            log.warning("Failed to refresh news calendar: %s", exc)
            return

        events: list[NewsEvent] = []
        for item in raw_events:
            try:
                event_date = datetime.fromisoformat(item["date"].replace("Z", "+00:00"))
                events.append(NewsEvent(
                    title=item.get("title", ""),
                    country=item.get("country", ""),
                    date=event_date.astimezone(timezone.utc),
                    impact=item.get("impact", "Low"),
                ))
            except (KeyError, ValueError):
                continue

        self._cache = events
        self._cache_time = now
        log.info("News calendar refreshed: %d events", len(events))

    def is_blackout(self, symbol: str) -> tuple[bool, str]:
        if not self.config.enabled:
            return False, ""

        self._refresh_cache()
        now = datetime.now(timezone.utc)
        currencies = self._symbol_currencies(symbol)

        window_start = now - timedelta(minutes=self.config.minutes_after)
        window_end = now + timedelta(minutes=self.config.minutes_before)

        for event in self._cache:
            if event.country not in currencies:
                continue
            if self.config.high_impact_only and event.impact.lower() != "high":
                continue
            if window_start <= event.date <= window_end:
                return True, f"{event.title} ({event.country}, {event.impact}) at {event.date.isoformat()}"

        return False, ""

    def next_high_impact_event(self, symbol: str) -> Optional[NewsEvent]:
        self._refresh_cache()
        now = datetime.now(timezone.utc)
        currencies = self._symbol_currencies(symbol)
        upcoming = [e for e in self._cache if e.country in currencies and e.impact.lower() == "high" and e.date > now]
        upcoming.sort(key=lambda e: e.date)
        return upcoming[0] if upcoming else None
