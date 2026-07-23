"""
Technical indicator calculations on a pandas OHLCV DataFrame (columns:
time, open, high, low, close, tick_volume). Pure functions, no MT5 or
broker dependency — this module is reusable for offline backtesting too.
"""
from __future__ import annotations

import numpy as np
import pandas as pd


def ema(series: pd.Series, length: int) -> pd.Series:
    return series.ewm(span=length, adjust=False).mean()


def atr(df: pd.DataFrame, length: int) -> pd.Series:
    high, low, close = df["high"], df["low"], df["close"]
    prev_close = close.shift(1)
    tr = pd.concat([
        high - low,
        (high - prev_close).abs(),
        (low - prev_close).abs(),
    ], axis=1).max(axis=1)
    return tr.ewm(alpha=1 / length, adjust=False).mean()


def rsi(series: pd.Series, length: int) -> pd.Series:
    delta = series.diff()
    gain = delta.clip(lower=0)
    loss = -delta.clip(upper=0)
    avg_gain = gain.ewm(alpha=1 / length, adjust=False).mean()
    avg_loss = loss.ewm(alpha=1 / length, adjust=False).mean()
    rs = avg_gain / avg_loss.replace(0, np.nan)
    return 100 - (100 / (1 + rs))


def macd(series: pd.Series, fast: int = 12, slow: int = 26, signal: int = 9):
    macd_line = ema(series, fast) - ema(series, slow)
    signal_line = ema(macd_line, signal)
    histogram = macd_line - signal_line
    return macd_line, signal_line, histogram


def adx(df: pd.DataFrame, length: int = 14) -> pd.Series:
    high, low, close = df["high"], df["low"], df["close"]
    up_move = high.diff()
    down_move = -low.diff()

    plus_dm = np.where((up_move > down_move) & (up_move > 0), up_move, 0.0)
    minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0.0)

    tr = atr(df, length) * length  # un-smoothed Wilder TR sum equivalent
    plus_di = 100 * pd.Series(plus_dm, index=df.index).ewm(alpha=1 / length, adjust=False).mean() / tr.replace(0, np.nan)
    minus_di = 100 * pd.Series(minus_dm, index=df.index).ewm(alpha=1 / length, adjust=False).mean() / tr.replace(0, np.nan)

    dx = (100 * (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan))
    return dx.ewm(alpha=1 / length, adjust=False).mean()


def supertrend(df: pd.DataFrame, factor: float = 3.0, atr_length: int = 10):
    atr_val = atr(df, atr_length)
    hl2 = (df["high"] + df["low"]) / 2
    basic_upper = hl2 + factor * atr_val
    basic_lower = hl2 - factor * atr_val

    final_upper = basic_upper.copy()
    final_lower = basic_lower.copy()
    direction = pd.Series(index=df.index, dtype=int)
    trend = pd.Series(index=df.index, dtype=float)

    for i in range(len(df)):
        if i == 0:
            direction.iloc[i] = -1
            trend.iloc[i] = final_lower.iloc[i]
            continue

        if basic_upper.iloc[i] < final_upper.iloc[i - 1] or df["close"].iloc[i - 1] > final_upper.iloc[i - 1]:
            final_upper.iloc[i] = basic_upper.iloc[i]
        else:
            final_upper.iloc[i] = final_upper.iloc[i - 1]

        if basic_lower.iloc[i] > final_lower.iloc[i - 1] or df["close"].iloc[i - 1] < final_lower.iloc[i - 1]:
            final_lower.iloc[i] = basic_lower.iloc[i]
        else:
            final_lower.iloc[i] = final_lower.iloc[i - 1]

        if df["close"].iloc[i] > final_upper.iloc[i - 1]:
            direction.iloc[i] = -1
        elif df["close"].iloc[i] < final_lower.iloc[i - 1]:
            direction.iloc[i] = 1
        else:
            direction.iloc[i] = direction.iloc[i - 1]

        trend.iloc[i] = final_lower.iloc[i] if direction.iloc[i] == -1 else final_upper.iloc[i]

    return trend, direction


def session_vwap(df: pd.DataFrame) -> pd.Series:
    """Resets at the start of each UTC calendar day, matching ta.vwap()'s
    default daily anchor in the Pine Script version."""
    typical = (df["high"] + df["low"] + df["close"]) / 3
    volume = df["tick_volume"]
    day = pd.to_datetime(df["time"], unit="s", utc=True).dt.date
    cum_pv = (typical * volume).groupby(day).cumsum()
    cum_v = volume.groupby(day).cumsum()
    return cum_pv / cum_v.replace(0, np.nan)


def relative_volume(df: pd.DataFrame, length: int = 20) -> pd.Series:
    avg = df["tick_volume"].rolling(length).mean()
    return df["tick_volume"] / avg.replace(0, np.nan)
