"""
Central configuration for the A+ Confluence Python/MT5 bridge.

Credentials are read from environment variables (or a local .env file, never
committed) rather than hardcoded — this bridge is meant to run unattended on
a VPS next to the MT5 terminal, so secrets need to live outside source control.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

from dotenv import load_dotenv

load_dotenv()


@dataclass
class MT5Credentials:
    login: int = int(os.getenv("MT5_LOGIN", "0"))
    password: str = os.getenv("MT5_PASSWORD", "")
    server: str = os.getenv("MT5_SERVER", "Exness-MT5Trial")
    terminal_path: str = os.getenv("MT5_TERMINAL_PATH", "")  # optional, e.g. "C:\\Program Files\\Exness MT5\\terminal64.exe"


@dataclass
class RiskConfig:
    risk_percent: float = float(os.getenv("RISK_PERCENT", "1.0"))
    max_risk_percent: float = 5.0          # hard ceiling, never overridden by risk_percent above
    min_rr: float = 3.0
    max_rr: float = 5.0
    partial_rr: float = 2.0
    partial_close_pct: float = 50.0
    max_spread_points: float = 35.0
    min_atr_pct: float = 0.03
    max_atr_pct: float = 1.20


@dataclass
class SessionConfig:
    trade_london: bool = True
    trade_new_york: bool = True
    trade_asian: bool = False
    asian_atr_override_pct: float = 0.50
    block_friday_late: bool = True
    friday_late_hour_utc: int = 18


@dataclass
class NewsConfig:
    enabled: bool = True
    minutes_before: int = 30
    minutes_after: int = 30
    high_impact_only: bool = True
    forexfactory_json_url: str = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"
    cache_ttl_seconds: int = 900


@dataclass
class TradingConfig:
    symbols: list[str] = field(default_factory=lambda: ["XAUUSD", "EURUSD", "GBPUSD", "NAS100", "US30"])
    timeframe: str = os.getenv("TIMEFRAME", "M15")
    magic_number: int = int(os.getenv("MAGIC_NUMBER", "20260723"))
    max_holding_bars: int = 48
    poll_seconds: int = 20

    mt5: MT5Credentials = field(default_factory=MT5Credentials)
    risk: RiskConfig = field(default_factory=RiskConfig)
    session: SessionConfig = field(default_factory=SessionConfig)
    news: NewsConfig = field(default_factory=NewsConfig)


CONFIG = TradingConfig()
