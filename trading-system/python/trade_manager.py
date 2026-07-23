"""
Python equivalent of TradeEngine.mqh: turns a validated TradeSignal into a
broker order, then manages the open position every poll cycle — partial
close at the partial-R target, breakeven, ATR/Supertrend trailing on the
runner, and the time-based exit for day-trading discipline.
"""
from __future__ import annotations

import logging
import time
from dataclasses import dataclass, field
from typing import Optional

import MetaTrader5 as mt5

import indicators as ind
from config import TradingConfig
from mt5_connector import MT5Connector
from risk_engine import RiskEngine
from signal_engine import TradeSignal

log = logging.getLogger("trade_manager")


@dataclass
class OpenTradeState:
    ticket: int
    partial_tp: float
    entry_time: float
    breakeven_done: bool = False
    partial_done: bool = False


class TradeManager:
    def __init__(self, connector: MT5Connector, risk_engine: RiskEngine, config: TradingConfig):
        self.connector = connector
        self.risk_engine = risk_engine
        self.config = config
        self._open_states: dict[str, OpenTradeState] = {}

    def has_open_position(self, symbol: str) -> bool:
        positions = self.connector.get_open_positions(magic_number=self.config.magic_number, symbol=symbol)
        return len(positions) > 0

    def execute_signal(self, symbol: str, signal: TradeSignal) -> bool:
        if not signal.is_valid:
            return False
        if self.has_open_position(symbol):
            log.debug("Skip %s — position already open (one per symbol)", symbol)
            return False

        spec = self.connector.get_symbol_spec(symbol)
        if spec is None:
            log.warning("No symbol spec for %s — cannot size trade", symbol)
            return False

        spread_points = self.connector.get_spread_points(symbol)
        spread_ok, spread_reason = self.risk_engine.validate_spread(spread_points)
        if not spread_ok:
            log.info("%s trade rejected: %s", symbol, spread_reason)
            return False

        stop_distance = abs(signal.entry - signal.stop_loss)
        balance = self.connector.get_balance()
        lot_decision = self.risk_engine.calculate_lot_size(balance, stop_distance, spec)
        if not lot_decision.accepted:
            log.info("%s trade rejected: %s", symbol, lot_decision.reject_reason)
            return False

        comment = f"APC-{'Long' if signal.is_buy else 'Short'}-RR{signal.risk_reward:.1f}"
        result = self.connector.open_trade(symbol, signal.is_buy, lot_decision.lot, signal.stop_loss,
                                             signal.take_profit, self.config.magic_number, comment)
        if result is None:
            return False

        ticket = getattr(result, "order", 0)
        self._open_states[symbol] = OpenTradeState(ticket=ticket, partial_tp=signal.partial_tp, entry_time=time.time())
        return True

    def manage_open_positions(self) -> None:
        positions = self.connector.get_open_positions(magic_number=self.config.magic_number)
        open_symbols = {p.symbol for p in positions}

        # Drop tracking for anything closed externally (SL/TP hit, manual close).
        for symbol in list(self._open_states.keys()):
            if symbol not in open_symbols:
                del self._open_states[symbol]

        for position in positions:
            symbol = position.symbol
            state = self._open_states.get(symbol)
            if state is None:
                continue  # opened outside this bridge (e.g. by the MT5 EA) — leave it alone

            is_buy = position.type == mt5.POSITION_TYPE_BUY
            tick = mt5.symbol_info_tick(symbol)
            if tick is None:
                continue
            current_price = tick.bid if is_buy else tick.ask

            partial_hit = current_price >= state.partial_tp if is_buy else current_price <= state.partial_tp

            if not state.partial_done and partial_hit:
                close_volume = round(position.volume * (self.config.risk.partial_close_pct / 100.0), 2)
                spec = self.connector.get_symbol_spec(symbol)
                if spec and close_volume >= spec.min_lot and close_volume < position.volume:
                    if self.connector.close_position(position, volume=close_volume):
                        state.partial_done = True
                        log.info("Partial close %.2f lots on %s", close_volume, symbol)

            if not state.breakeven_done and partial_hit:
                if self.connector.modify_position(position.ticket, position.price_open, position.tp):
                    state.breakeven_done = True
                    log.info("Breakeven set on %s", symbol)

            if state.breakeven_done:
                rates = self.connector.get_rates(symbol, mt5.TIMEFRAME_M15, 200)
                if rates is not None and len(rates) > 20:
                    import pandas as pd
                    df = pd.DataFrame(rates)
                    trend, direction = ind.supertrend(df, 3.0, 10)
                    st_value = trend.iloc[-1]
                    st_dir = direction.iloc[-1]
                    current_sl = position.sl
                    if is_buy and st_dir < 0 and st_value > current_sl and st_value < current_price:
                        self.connector.modify_position(position.ticket, st_value, position.tp)
                    elif not is_buy and st_dir > 0 and st_value < current_sl and st_value > current_price:
                        self.connector.modify_position(position.ticket, st_value, position.tp)

            bars_held_seconds = time.time() - state.entry_time
            max_holding_seconds = self.config.max_holding_bars * 15 * 60  # assumes M15; adjust for other timeframes
            if bars_held_seconds >= max_holding_seconds:
                if self.connector.close_position(position):
                    log.info("Time-based close on %s after %.0f minutes", symbol, bars_held_seconds / 60)
                    del self._open_states[symbol]
