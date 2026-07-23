"""
Market structure + Smart Money Concepts + confluence decision engine.
This is the Python equivalent of MarketStructure.mqh + SMC.mqh + the
EvaluateAndTrade() confluence block in AplusConfluenceEA.mq5 — kept in
lockstep with those so a signal fired here means the same thing it would
mean on the chart or in the live EA.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

import numpy as np
import pandas as pd

import indicators as ind
from config import TradingConfig


@dataclass
class SymbolStructureState:
    last_swing_high: float = 0.0
    prev_swing_high: float = 0.0
    last_swing_low: float = 0.0
    prev_swing_low: float = 0.0
    last_high_type: int = 0     # 1 = HH, -1 = LH
    last_low_type: int = 0      # 1 = HL, -1 = LL
    structure_bias: int = 0     # 1 bullish, -1 bearish, 0 undefined

    bull_ob: Optional[tuple[float, float]] = None   # (top, bottom)
    bear_ob: Optional[tuple[float, float]] = None
    bull_fvg: Optional[tuple[float, float]] = None
    bear_fvg: Optional[tuple[float, float]] = None

    last_sweep_low_idx: Optional[int] = None
    last_sweep_high_idx: Optional[int] = None


@dataclass
class TradeSignal:
    is_valid: bool
    is_buy: bool = False
    entry: float = 0.0
    stop_loss: float = 0.0
    take_profit: float = 0.0
    partial_tp: float = 0.0
    risk_reward: float = 0.0
    reason: str = ""


def _find_pivot(highs_or_lows: np.ndarray, idx: int, left: int, right: int, is_high: bool) -> bool:
    if idx - left < 0 or idx + right >= len(highs_or_lows):
        return False
    center = highs_or_lows[idx]
    window = np.concatenate([highs_or_lows[idx - left:idx], highs_or_lows[idx + 1:idx + right + 1]])
    return bool(np.all(window < center)) if is_high else bool(np.all(window > center))


def update_structure(state: SymbolStructureState, df: pd.DataFrame, pivot_left: int = 5, pivot_right: int = 5) -> None:
    """Scans for a newly confirmable pivot at (len-1-pivot_right) and updates
    swing/structure state in place. Call once per newly closed bar."""
    highs = df["high"].to_numpy()
    lows = df["low"].to_numpy()
    pivot_idx = len(df) - 1 - pivot_right
    if pivot_idx < pivot_left:
        return

    if _find_pivot(highs, pivot_idx, pivot_left, pivot_right, is_high=True):
        ph = highs[pivot_idx]
        state.last_high_type = 1 if state.prev_swing_high == 0 else (1 if ph > state.prev_swing_high else -1)
        state.prev_swing_high = state.last_swing_high
        state.last_swing_high = ph

    if _find_pivot(lows, pivot_idx, pivot_left, pivot_right, is_high=False):
        pl = lows[pivot_idx]
        state.last_low_type = 1 if state.prev_swing_low == 0 else (1 if pl > state.prev_swing_low else -1)
        state.prev_swing_low = state.last_swing_low
        state.last_swing_low = pl

    if state.last_high_type == 1 and state.last_low_type == 1:
        state.structure_bias = 1
    elif state.last_high_type == -1 and state.last_low_type == -1:
        state.structure_bias = -1
    else:
        state.structure_bias = 0


def detect_bos(state: SymbolStructureState, prev_close: float, curr_close: float) -> tuple[bool, bool]:
    bos_up = state.last_swing_high > 0 and prev_close <= state.last_swing_high < curr_close
    bos_down = state.last_swing_low > 0 and prev_close >= state.last_swing_low > curr_close
    return bos_up, bos_down


def update_order_blocks(state: SymbolStructureState, df: pd.DataFrame, bos_up: bool, bos_down: bool, scan_bars: int = 15) -> None:
    if not (bos_up or bos_down):
        return
    opens = df["open"].to_numpy()
    highs = df["high"].to_numpy()
    lows = df["low"].to_numpy()
    closes = df["close"].to_numpy()
    n = len(df)

    if bos_up:
        for i in range(n - 2, max(n - 2 - scan_bars, -1), -1):
            if closes[i] < opens[i]:
                state.bull_ob = (highs[i], lows[i])
                break

    if bos_down:
        for i in range(n - 2, max(n - 2 - scan_bars, -1), -1):
            if closes[i] > opens[i]:
                state.bear_ob = (highs[i], lows[i])
                break


def update_fair_value_gaps(state: SymbolStructureState, df: pd.DataFrame) -> None:
    if len(df) < 3:
        return
    high2, low0 = df["high"].iloc[-3], df["low"].iloc[-1]
    low2, high0 = df["low"].iloc[-3], df["high"].iloc[-1]
    if low0 > high2:
        state.bull_fvg = (low0, high2)
    if high0 < low2:
        state.bear_fvg = (low2, high0)


def update_liquidity_sweeps(state: SymbolStructureState, df: pd.DataFrame) -> None:
    idx = len(df) - 1
    high, low, close = df["high"].iloc[-1], df["low"].iloc[-1], df["close"].iloc[-1]
    if state.last_swing_low > 0 and low < state.last_swing_low < close:
        state.last_sweep_low_idx = idx
    if state.last_swing_high > 0 and high > state.last_swing_high > close:
        state.last_sweep_high_idx = idx


def _in_zone(price_high: float, price_low: float, price_close: float, zone: Optional[tuple[float, float]], bullish: bool) -> bool:
    if zone is None:
        return False
    top, bot = zone
    if bullish:
        return price_low <= top and price_high >= bot and price_close > bot
    return price_high >= bot and price_low <= top and price_close < top


def evaluate_confluence(df: pd.DataFrame, state: SymbolStructureState, config: TradingConfig) -> TradeSignal:
    """Runs the full confluence stack on the latest closed bar of `df` and
    returns a TradeSignal. `df` must have at least ~250 bars of history for
    EMA200/ADX/Supertrend to be meaningful."""
    if len(df) < 210:
        return TradeSignal(False, reason="insufficient history")

    close = df["close"]
    ema_fast = ind.ema(close, 20).iloc[-1]
    ema_mid = ind.ema(close, 50).iloc[-1]
    ema_slow = ind.ema(close, 200).iloc[-1]
    atr_series = ind.atr(df, 14)
    atr_val = atr_series.iloc[-1]
    vwap_val = ind.session_vwap(df).iloc[-1]
    st_trend, st_dir = ind.supertrend(df, 3.0, 10)
    st_direction = st_dir.iloc[-1]
    adx_val = ind.adx(df, 14).iloc[-1]
    rsi_val = ind.rsi(close, 14).iloc[-1]
    _, _, macd_hist = ind.macd(close, 12, 26, 9)
    rel_vol = ind.relative_volume(df, 20).iloc[-1]

    last_close = close.iloc[-1]
    prev_close = close.iloc[-2]

    update_structure(state, df)
    bos_up, bos_down = detect_bos(state, prev_close, last_close)
    update_order_blocks(state, df, bos_up, bos_down)
    update_fair_value_gaps(state, df)
    update_liquidity_sweeps(state, df)

    trend_bull = last_close > vwap_val and ema_fast > ema_mid > ema_slow and st_direction < 0 and adx_val > 20
    trend_bear = last_close < vwap_val and ema_fast < ema_mid < ema_slow and st_direction > 0 and adx_val > 20

    momentum_bull = rsi_val > 50 and macd_hist.iloc[-1] > macd_hist.iloc[-2]
    momentum_bear = rsi_val < 50 and macd_hist.iloc[-1] < macd_hist.iloc[-2]

    volume_confirm = rel_vol > 1.1

    high, low = df["high"].iloc[-1], df["low"].iloc[-1]
    zone_bull = _in_zone(high, low, last_close, state.bull_ob, True) or _in_zone(high, low, last_close, state.bull_fvg, True)
    zone_bear = _in_zone(high, low, last_close, state.bear_ob, False) or _in_zone(high, low, last_close, state.bear_fvg, False)

    idx = len(df) - 1
    sweep_low_recent = state.last_sweep_low_idx is not None and (idx - state.last_sweep_low_idx) <= 6
    sweep_high_recent = state.last_sweep_high_idx is not None and (idx - state.last_sweep_high_idx) <= 6

    mid = (state.last_swing_high + state.last_swing_low) / 2 if state.last_swing_high and state.last_swing_low else None
    discount_ok = mid is not None and last_close < mid
    premium_ok = mid is not None and last_close > mid

    long_signal = (trend_bull and state.structure_bias == 1 and zone_bull and sweep_low_recent and
                   momentum_bull and volume_confirm and discount_ok)
    short_signal = (trend_bear and state.structure_bias == -1 and zone_bear and sweep_high_recent and
                     momentum_bear and volume_confirm and premium_ok)

    if not long_signal and not short_signal:
        return TradeSignal(False, reason="confluence not met")

    if long_signal:
        ob_bot = state.bull_ob[1] if state.bull_ob else state.last_swing_low
        sl = min(ob_bot, state.last_swing_low) - atr_val * 0.25
        sl_dist = last_close - sl
        if sl_dist <= 0 or state.last_swing_high <= 0:
            return TradeSignal(False, reason="invalid stop distance")
        structural_rr = (state.last_swing_high - last_close) / sl_dist
        if structural_rr < config.risk.min_rr:
            return TradeSignal(False, reason=f"structural RR {structural_rr:.2f} below floor {config.risk.min_rr}")
        final_rr = max(config.risk.min_rr, min(config.risk.max_rr, structural_rr))
        tp = last_close + sl_dist * final_rr
        partial_tp = last_close + sl_dist * config.risk.partial_rr
        return TradeSignal(True, is_buy=True, entry=last_close, stop_loss=sl, take_profit=tp,
                            partial_tp=partial_tp, risk_reward=final_rr, reason="long confluence")

    ob_top = state.bear_ob[0] if state.bear_ob else state.last_swing_high
    sl = max(ob_top, state.last_swing_high) + atr_val * 0.25
    sl_dist = sl - last_close
    if sl_dist <= 0 or state.last_swing_low <= 0:
        return TradeSignal(False, reason="invalid stop distance")
    structural_rr = (last_close - state.last_swing_low) / sl_dist
    if structural_rr < config.risk.min_rr:
        return TradeSignal(False, reason=f"structural RR {structural_rr:.2f} below floor {config.risk.min_rr}")
    final_rr = max(config.risk.min_rr, min(config.risk.max_rr, structural_rr))
    tp = last_close - sl_dist * final_rr
    partial_tp = last_close - sl_dist * config.risk.partial_rr
    return TradeSignal(True, is_buy=False, entry=last_close, stop_loss=sl, take_profit=tp,
                        partial_tp=partial_tp, risk_reward=final_rr, reason="short confluence")
