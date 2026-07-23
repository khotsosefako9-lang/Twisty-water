"""
Reads closed-trade history from MT5 and computes the statistical-edge
metrics the strategy is judged on: win rate, avg win/loss, profit factor,
Sharpe ratio, max drawdown, expectancy, avg holding time, trade count.
Exports a CSV trade log plus a text summary report.
"""
from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime

import numpy as np
import pandas as pd
import MetaTrader5 as mt5

log = logging.getLogger("performance_report")


@dataclass
class PerformanceStats:
    total_trades: int
    win_trades: int
    loss_trades: int
    win_rate_pct: float
    avg_win: float
    avg_loss: float
    profit_factor: float
    expectancy: float
    sharpe_ratio: float
    max_drawdown_pct: float
    avg_holding_minutes: float
    net_profit: float


def fetch_closed_trades(magic_number: int, from_date: datetime, to_date: datetime) -> pd.DataFrame:
    deals = mt5.history_deals_get(from_date, to_date)
    if deals is None:
        return pd.DataFrame()

    rows = []
    for deal in deals:
        if deal.magic != magic_number:
            continue
        if deal.entry != mt5.DEAL_ENTRY_OUT:
            continue
        rows.append({
            "ticket": deal.ticket,
            "position_id": deal.position_id,
            "symbol": deal.symbol,
            "time": datetime.fromtimestamp(deal.time),
            "profit": deal.profit + deal.swap + deal.commission,
            "volume": deal.volume,
        })
    return pd.DataFrame(rows)


def compute_stats(trades: pd.DataFrame, starting_balance: float, risk_free_rate: float = 0.0) -> PerformanceStats:
    if trades.empty:
        return PerformanceStats(0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

    wins = trades[trades["profit"] > 0]
    losses = trades[trades["profit"] <= 0]

    total = len(trades)
    win_count = len(wins)
    loss_count = len(losses)
    win_rate = 100.0 * win_count / total if total else 0.0

    avg_win = wins["profit"].mean() if win_count else 0.0
    avg_loss = losses["profit"].mean() if loss_count else 0.0

    gross_profit = wins["profit"].sum()
    gross_loss = abs(losses["profit"].sum())
    profit_factor = gross_profit / gross_loss if gross_loss > 0 else (999.0 if gross_profit > 0 else 0.0)

    win_prob = win_count / total if total else 0.0
    loss_prob = 1 - win_prob
    expectancy = (win_prob * avg_win) + (loss_prob * avg_loss)

    equity_curve = starting_balance + trades["profit"].cumsum()
    running_max = equity_curve.cummax()
    drawdown_pct = ((running_max - equity_curve) / running_max.replace(0, np.nan)) * 100
    max_drawdown_pct = drawdown_pct.max() if not drawdown_pct.empty else 0.0

    daily_returns = trades.set_index("time")["profit"].resample("D").sum()
    if daily_returns.std(ddof=0) > 0:
        sharpe = (daily_returns.mean() - risk_free_rate) / daily_returns.std(ddof=0) * np.sqrt(252)
    else:
        sharpe = 0.0

    net_profit = trades["profit"].sum()

    return PerformanceStats(
        total_trades=total,
        win_trades=win_count,
        loss_trades=loss_count,
        win_rate_pct=win_rate,
        avg_win=avg_win,
        avg_loss=avg_loss,
        profit_factor=profit_factor,
        expectancy=expectancy,
        sharpe_ratio=sharpe,
        max_drawdown_pct=float(max_drawdown_pct) if max_drawdown_pct == max_drawdown_pct else 0.0,  # NaN guard
        avg_holding_minutes=0.0,  # placeholder: needs entry-deal timestamps joined by position_id (mt5.history_deals_get with DEAL_ENTRY_IN) to compute
        net_profit=net_profit,
    )


def export_trade_log(trades: pd.DataFrame, path: str) -> None:
    trades.to_csv(path, index=False)
    log.info("Trade log exported to %s (%d rows)", path, len(trades))


def render_summary(stats: PerformanceStats) -> str:
    return (
        "==== A+ Confluence Performance Summary ====\n"
        f"Total Trades      : {stats.total_trades}\n"
        f"Win / Loss         : {stats.win_trades} / {stats.loss_trades}\n"
        f"Win Rate            : {stats.win_rate_pct:.2f}%\n"
        f"Average Win         : {stats.avg_win:.2f}\n"
        f"Average Loss        : {stats.avg_loss:.2f}\n"
        f"Profit Factor       : {stats.profit_factor:.2f}\n"
        f"Expectancy / Trade  : {stats.expectancy:.2f}\n"
        f"Sharpe Ratio (ann.) : {stats.sharpe_ratio:.2f}\n"
        f"Max Drawdown        : {stats.max_drawdown_pct:.2f}%\n"
        f"Net Profit          : {stats.net_profit:.2f}\n"
    )
