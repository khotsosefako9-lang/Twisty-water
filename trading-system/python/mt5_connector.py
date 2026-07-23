"""
Thin wrapper around the MetaTrader5 Python package: connect, read account
state, read/modify/close positions. Every other module goes through this
instead of calling the `MetaTrader5` package directly, so there is exactly
one place that knows how to talk to the terminal.
"""
from __future__ import annotations

import logging
import time
from dataclasses import dataclass
from typing import Optional

import MetaTrader5 as mt5

from config import MT5Credentials

log = logging.getLogger("mt5_connector")


@dataclass
class SymbolSpec:
    symbol: str
    digits: int
    point: float
    tick_size: float
    tick_value: float
    min_lot: float
    max_lot: float
    lot_step: float
    contract_size: float


class MT5Connector:
    def __init__(self, credentials: MT5Credentials):
        self.credentials = credentials
        self._connected = False

    def connect(self, retries: int = 5, retry_delay_seconds: float = 3.0) -> bool:
        for attempt in range(1, retries + 1):
            kwargs = {}
            if self.credentials.terminal_path:
                kwargs["path"] = self.credentials.terminal_path

            if not mt5.initialize(**kwargs):
                log.warning("mt5.initialize failed (attempt %d/%d): %s", attempt, retries, mt5.last_error())
                time.sleep(retry_delay_seconds)
                continue

            if self.credentials.login:
                authorized = mt5.login(
                    self.credentials.login,
                    password=self.credentials.password,
                    server=self.credentials.server,
                )
                if not authorized:
                    log.warning("mt5.login failed (attempt %d/%d): %s", attempt, retries, mt5.last_error())
                    mt5.shutdown()
                    time.sleep(retry_delay_seconds)
                    continue

            self._connected = True
            log.info("Connected to MT5 terminal, account=%s server=%s", self.credentials.login, self.credentials.server)
            return True

        log.error("Could not connect to MT5 after %d attempts", retries)
        return False

    def ensure_connected(self) -> bool:
        """Reconnect handling: call before any trading action."""
        if self._connected and mt5.terminal_info() is not None:
            return True
        log.warning("MT5 connection lost — attempting reconnect")
        self._connected = False
        return self.connect()

    def disconnect(self) -> None:
        mt5.shutdown()
        self._connected = False

    # --- Account ---
    def get_balance(self) -> float:
        info = mt5.account_info()
        return float(info.balance) if info else 0.0

    def get_equity(self) -> float:
        info = mt5.account_info()
        return float(info.equity) if info else 0.0

    def get_currency(self) -> str:
        info = mt5.account_info()
        return info.currency if info else "ZAR"

    # --- Symbols ---
    def get_symbol_spec(self, symbol: str) -> Optional[SymbolSpec]:
        if not mt5.symbol_select(symbol, True):
            log.error("Symbol not available on broker: %s", symbol)
            return None
        info = mt5.symbol_info(symbol)
        if info is None:
            return None
        return SymbolSpec(
            symbol=symbol,
            digits=info.digits,
            point=info.point,
            tick_size=info.trade_tick_size,
            tick_value=info.trade_tick_value,
            min_lot=info.volume_min,
            max_lot=info.volume_max,
            lot_step=info.volume_step,
            contract_size=info.trade_contract_size,
        )

    def get_spread_points(self, symbol: str) -> float:
        tick = mt5.symbol_info_tick(symbol)
        info = mt5.symbol_info(symbol)
        if tick is None or info is None or info.point <= 0:
            return 0.0
        return (tick.ask - tick.bid) / info.point

    def get_rates(self, symbol: str, timeframe: int, count: int):
        rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, count)
        return rates

    # --- Positions ---
    def get_open_positions(self, magic_number: Optional[int] = None, symbol: Optional[str] = None):
        positions = mt5.positions_get(symbol=symbol) if symbol else mt5.positions_get()
        if positions is None:
            return []
        if magic_number is not None:
            positions = [p for p in positions if p.magic == magic_number]
        return list(positions)

    def open_trade(self, symbol: str, is_buy: bool, lot: float, sl: float, tp: float,
                   magic_number: int, comment: str, deviation_points: int = 20):
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            log.error("No tick data for %s — cannot open trade", symbol)
            return None

        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": lot,
            "type": mt5.ORDER_TYPE_BUY if is_buy else mt5.ORDER_TYPE_SELL,
            "price": tick.ask if is_buy else tick.bid,
            "sl": sl,
            "tp": tp,
            "deviation": deviation_points,
            "magic": magic_number,
            "comment": comment,
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
            log.error("order_send failed for %s: %s", symbol, result)
            return None
        log.info("Opened %s %s lot=%.2f sl=%.5f tp=%.5f ticket=%s", "BUY" if is_buy else "SELL",
                  symbol, lot, sl, tp, getattr(result, "order", None))
        return result

    def modify_position(self, ticket: int, sl: float, tp: float) -> bool:
        request = {
            "action": mt5.TRADE_ACTION_SLTP,
            "position": ticket,
            "sl": sl,
            "tp": tp,
        }
        result = mt5.order_send(request)
        return result is not None and result.retcode == mt5.TRADE_RETCODE_DONE

    def close_position(self, position, volume: Optional[float] = None) -> bool:
        symbol = position.symbol
        tick = mt5.symbol_info_tick(symbol)
        if tick is None:
            return False
        is_buy = position.type == mt5.POSITION_TYPE_BUY
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": volume if volume is not None else position.volume,
            "type": mt5.ORDER_TYPE_SELL if is_buy else mt5.ORDER_TYPE_BUY,
            "position": position.ticket,
            "price": tick.bid if is_buy else tick.ask,
            "deviation": 20,
            "magic": position.magic,
            "comment": "APC-close",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }
        result = mt5.order_send(request)
        return result is not None and result.retcode == mt5.TRADE_RETCODE_DONE
