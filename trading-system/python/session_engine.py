"""
Python mirror of SessionEngine.mqh. All checks use UTC directly since the
Python bridge talks to the MT5 API in broker server time via timestamps
that we convert once here, rather than juggling timezones throughout.
"""
from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum

from config import SessionConfig


class Session(Enum):
    NONE = "off-session"
    ASIAN = "asian"
    LONDON = "london"
    NEW_YORK = "new_york"
    OVERLAP = "overlap"


class SessionEngine:
    def __init__(self, config: SessionConfig):
        self.config = config

    def current_session(self, now_utc: datetime | None = None) -> Session:
        now_utc = now_utc or datetime.now(timezone.utc)
        h = now_utc.hour
        london = 7 <= h < 16
        new_york = 12 <= h < 21
        if london and new_york:
            return Session.OVERLAP
        if london:
            return Session.LONDON
        if new_york:
            return Session.NEW_YORK
        if h >= 23 or h < 7:
            return Session.ASIAN
        return Session.NONE

    def is_friday_late(self, now_utc: datetime | None = None) -> bool:
        if not self.config.block_friday_late:
            return False
        now_utc = now_utc or datetime.now(timezone.utc)
        return now_utc.weekday() == 4 and now_utc.hour >= self.config.friday_late_hour_utc

    def is_session_allowed(self, atr_pct: float, now_utc: datetime | None = None) -> tuple[bool, str]:
        if self.is_friday_late(now_utc):
            return False, "Friday late session blocked"

        session = self.current_session(now_utc)
        if session == Session.OVERLAP:
            if self.config.trade_london or self.config.trade_new_york:
                return True, ""
        elif session == Session.LONDON:
            if self.config.trade_london:
                return True, ""
        elif session == Session.NEW_YORK:
            if self.config.trade_new_york:
                return True, ""
        elif session == Session.ASIAN:
            if self.config.trade_asian and atr_pct >= self.config.asian_atr_override_pct:
                return True, ""
            return False, "Asian session blocked (ATR% override not met)"

        return False, "outside configured trading sessions"
