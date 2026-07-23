# Suggested Starting Parameters

These are **starting points for forward-testing**, derived from each
instrument's typical intraday volatility and spread characteristics — not
guaranteed-optimal values. Re-validate on your broker's actual historical
spread/slippage before trusting them with real size. Every parameter here
maps directly to an input in the Pine Script, the MQL5 EA, and
`config.py`/`RiskConfig`/`Indicators.mqh` inputs.

Shared across all symbols unless noted: EMA 20/50/200, RSI(14)/50 midline,
MACD(12,26,9), min RR 1:3 / max RR 1:5, partial at 1:2R / 50%, risk 1%.

## XAUUSD (Gold)

| Timeframe | ADX threshold | ATR% band | Relative Volume | Sweep lookback | Pivot L/R | Notes |
|---|---|---|---|---|---|---|
| M5  | 22 | 0.05% – 0.90% | 1.2x | 5 | 4/4 | Gold spikes hard around US data; keep ATR ceiling tight to reject spike bars. |
| M15 | 20 | 0.05% – 1.20% | 1.15x | 6 | 5/5 | Default configuration in the shipped strategy — best balance of signal frequency vs quality. |
| M30 | 18 | 0.06% – 1.40% | 1.1x | 6 | 6/6 | Fewer, higher-conviction setups; widen ATR SL buffer to 0.35x. |

Best sessions: London open (volatility expansion) and NY/London overlap.
Widen `maxSpreadPoints` vs FX pairs — gold spreads run wider by nature.

## EURUSD

| Timeframe | ADX threshold | ATR% band | Relative Volume | Sweep lookback | Pivot L/R | Notes |
|---|---|---|---|---|---|---|
| M5  | 20 | 0.02% – 0.35% | 1.1x | 5 | 4/4 | Tightest spread of the set — good for higher-frequency M5 if latency allows. |
| M15 | 20 | 0.03% – 0.50% | 1.1x | 6 | 5/5 | Default. |
| M30 | 18 | 0.03% – 0.60% | 1.05x | 6 | 6/6 | Structure is cleaner at M30; expect fewer but cleaner BOS events. |

Best sessions: London/NY overlap has the strongest directional follow-through
for EURUSD specifically — consider restricting to overlap-only at M5.

## GBPUSD

| Timeframe | ADX threshold | ATR% band | Relative Volume | Sweep lookback | Pivot L/R | Notes |
|---|---|---|---|---|---|---|
| M5  | 22 | 0.03% – 0.45% | 1.15x | 5 | 4/4 | More prone to false breakouts/liquidity grabs than EURUSD — the sweep-recency filter matters more here. |
| M15 | 20 | 0.03% – 0.60% | 1.1x | 6 | 5/5 | Default. |
| M30 | 18 | 0.04% – 0.70% | 1.05x | 6 | 6/6 | |

Best sessions: London (GBP's home session) and the overlap. Avoid holding
into the last hour of NY on GBP — reversion is common.

## NAS100

| Timeframe | ADX threshold | ATR% band | Relative Volume | Sweep lookback | Pivot L/R | Notes |
|---|---|---|---|---|---|---|
| M5  | 24 | 0.06% – 1.00% | 1.3x | 4 | 4/4 | Index moves fast; require a higher ADX floor to avoid chasing chop between data prints. |
| M15 | 22 | 0.07% – 1.30% | 1.2x | 5 | 5/5 | Default-adjacent — raise ADX threshold to 22 vs the FX default of 20. |
| M30 | 20 | 0.08% – 1.60% | 1.15x | 6 | 6/6 | |

Best sessions: NY session (index's home market), especially the first two
hours after the US cash open and the last hour into the close.

## US30

| Timeframe | ADX threshold | ATR% band | Relative Volume | Sweep lookback | Pivot L/R | Notes |
|---|---|---|---|---|---|---|
| M5  | 24 | 0.05% – 0.90% | 1.25x | 4 | 4/4 | Similar profile to NAS100 but slightly lower beta — same ADX floor recommended. |
| M15 | 22 | 0.06% – 1.10% | 1.15x | 5 | 5/5 | |
| M30 | 20 | 0.07% – 1.30% | 1.1x | 6 | 6/6 | |

Best sessions: NY session, same as NAS100.

## General tuning notes

- **Lower timeframes (M5)** need tighter ATR ceilings and shorter sweep
  lookback — noise increases faster than signal as timeframe shrinks.
- **Higher ADX thresholds on indices** reflect that NAS100/US30 trend more
  violently but also chop more violently between trends than FX majors —
  the regime filter needs to work harder.
- **Volatility Indexes** (if available on your Exness account) were not
  benchmarked here since specifications vary by broker/index provider —
  start from the M15 Gold row (similar volatility character) and adjust
  ATR% bands after observing at least 2–3 weeks of live ATR readings on the
  specific index your account can access.
- Every "best sessions" recommendation is a **default toggle**, not a hard
  rule baked into logic — `InpTradeLondon`/`InpTradeNewYork`/session inputs
  can be adjusted per symbol if you run separate EA instances per chart.
