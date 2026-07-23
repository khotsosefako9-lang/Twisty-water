"""
A+ Confluence — Python/MT5 Bridge entry point.

Runs the full pipeline every `poll_seconds`: pull rates -> evaluate
confluence -> gate on session/news/volatility/spread -> size and execute ->
manage open positions. Intended to run as a long-lived process on the same
machine/VPS as the MT5 terminal (or a separate one, reachable via the MT5
Python API's own connection, which does not require the terminal to be on
the same host as long as the terminal itself is logged in and reachable).

This bridge is independent from the MQL5 EA — run one or the other per
account/magic-number combination to avoid double-trading the same signals.
"""
from __future__ import annotations

import logging
import time
from datetime import datetime, timedelta, timezone

import pandas as pd
import MetaTrader5 as mt5

from config import CONFIG
from mt5_connector import MT5Connector
from news_filter import NewsFilter
from performance_report import compute_stats, export_trade_log, fetch_closed_trades, render_summary
from risk_engine import RiskEngine
from session_engine import SessionEngine
from signal_engine import SymbolStructureState, evaluate_confluence
from trade_manager import TradeManager

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
log = logging.getLogger("main")

TIMEFRAME_MAP = {
    "M1": mt5.TIMEFRAME_M1, "M5": mt5.TIMEFRAME_M5, "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30, "H1": mt5.TIMEFRAME_H1, "H4": mt5.TIMEFRAME_H4,
}


def rates_to_dataframe(rates) -> pd.DataFrame:
    df = pd.DataFrame(rates)
    return df


def run() -> None:
    connector = MT5Connector(CONFIG.mt5)
    if not connector.connect():
        log.error("Could not establish MT5 connection — exiting")
        return

    risk_engine = RiskEngine(CONFIG.risk)
    session_engine = SessionEngine(CONFIG.session)
    news_filter = NewsFilter(CONFIG.news)
    trade_manager = TradeManager(connector, risk_engine, CONFIG)

    structure_states = {symbol: SymbolStructureState() for symbol in CONFIG.symbols}
    timeframe = TIMEFRAME_MAP.get(CONFIG.timeframe, mt5.TIMEFRAME_M15)
    last_bar_time: dict[str, int] = {}

    log.info("A+ Confluence bridge started. Watching %s on %s, risk=%.1f%%",
             CONFIG.symbols, CONFIG.timeframe, risk_engine.risk_percent)

    try:
        while True:
            if not connector.ensure_connected():
                time.sleep(5)
                continue

            for symbol in CONFIG.symbols:
                try:
                    process_symbol(symbol, connector, risk_engine, session_engine, news_filter,
                                    trade_manager, structure_states, timeframe, last_bar_time)
                except Exception:
                    log.exception("Unhandled error processing %s — continuing to next symbol", symbol)

            trade_manager.manage_open_positions()
            time.sleep(CONFIG.poll_seconds)

    except KeyboardInterrupt:
        log.info("Shutdown requested")
    finally:
        connector.disconnect()


def process_symbol(symbol, connector, risk_engine, session_engine, news_filter,
                    trade_manager, structure_states, timeframe, last_bar_time) -> None:
    rates = connector.get_rates(symbol, timeframe, 300)
    if rates is None or len(rates) < 210:
        log.debug("Not enough history yet for %s", symbol)
        return

    df = rates_to_dataframe(rates)
    latest_bar_time = int(df["time"].iloc[-1])
    if last_bar_time.get(symbol) == latest_bar_time:
        return  # only evaluate once per newly closed bar, same as the EA
    last_bar_time[symbol] = latest_bar_time

    state = structure_states[symbol]
    signal = evaluate_confluence(df, state, CONFIG)

    if not signal.is_valid:
        log.debug("%s: no trade (%s)", symbol, signal.reason)
        return

    atr_val = df["high"].iloc[-14:].max() - df["low"].iloc[-14:].min()  # coarse ATR proxy for the session/vol gates below
    atr_pct = (atr_val / df["close"].iloc[-1]) * 100.0

    session_ok, session_reason = session_engine.is_session_allowed(atr_pct)
    if not session_ok:
        log.info("%s signal (%s) rejected: %s", symbol, "BUY" if signal.is_buy else "SELL", session_reason)
        return

    news_blackout, news_reason = news_filter.is_blackout(symbol)
    if news_blackout:
        log.info("%s signal rejected: %s", symbol, news_reason)
        return

    log.info("%s %s signal: entry=%.5f sl=%.5f tp=%.5f RR=1:%.2f (%s)",
              symbol, "BUY" if signal.is_buy else "SELL", signal.entry, signal.stop_loss,
              signal.take_profit, signal.risk_reward, signal.reason)

    trade_manager.execute_signal(symbol, signal)


def generate_report(days_back: int = 30, output_csv: str = "trade_log.csv") -> None:
    """Standalone report generator — run separately from the live loop,
    e.g. `python main.py report` or on a daily cron."""
    connector = MT5Connector(CONFIG.mt5)
    if not connector.connect():
        return
    try:
        to_date = datetime.now(timezone.utc)
        from_date = to_date - timedelta(days=days_back)
        trades = fetch_closed_trades(CONFIG.magic_number, from_date, to_date)
        if trades.empty:
            log.info("No closed trades in the last %d days", days_back)
            return
        export_trade_log(trades, output_csv)
        stats = compute_stats(trades, starting_balance=connector.get_balance())
        print(render_summary(stats))
    finally:
        connector.disconnect()


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "report":
        generate_report()
    else:
        run()
