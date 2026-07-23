# Troubleshooting

## TradingView (Pine Script)

**"Strategy generates almost no trades."**
This is by design — confluence requires trend, structure, zone, sweep,
momentum, volume, session, volatility, and RR to all align simultaneously.
If you need more signal frequency for testing, temporarily lower
`InpAdxThreshold`/`adxThreshold` or widen the ATR% band; do not remove
confluence legs, since that changes what the system is.

**"Pivot-based structure looks like it repaints."**
It doesn't, but it does *lag*: a pivot at bar N is only known once
`pivotRight` bars have closed after it. That is a confirmation delay, not
repainting — the pivot's price value never changes retroactively. If you
need faster (less accurate) structure, reduce `pivotRight`, understanding
that shrinks the confirmation window and increases false pivots.

**"Backtest net profit doesn't match my intuition for the risk% used."**
`initial_capital` in the `strategy()` declaration must match the account
size you're mentally benchmarking against — the built-in Strategy Tester
computes % returns relative to that value, not to any external number.

## MetaTrader 5 / MQL5 EA

**"EA won't compile — 'declaration already met' / duplicate identifier."**
Every `.mqh` in `Include/AplusConfluence/` has `#ifndef/#define/#endif`
guards specifically to prevent this when one header is pulled in both
directly by the EA and transitively via another header (e.g. `Indicators.mqh`
via `TradeEngine.mqh`). If you added a new header without a guard, add one
following the existing pattern.

**"EA compiles but never places a trade."**
Check the Experts/Journal tab for the rejection reason — every filter logs
why a setup was declined (`CLogger.Info`/`Warn`). Common causes: AutoTrading
disabled, `TERMINAL_TRADE_ALLOWED` off, algo trading permission not granted
per-symbol, or simply that confluence hasn't aligned yet (this is normal and
expected most of the time).

**"CalendarValueHistory returns 0 events / never blocks trades."**
The MT5 Economic Calendar requires the terminal to have synced calendar data
at least once — open the built-in Calendar tab in the terminal manually
once to force a sync, especially on a fresh VPS install. If calendar sync is
unavailable on your VPS, use the CSV fallback (`InpNewsCsvFallbackFile`,
placed in `MQL5/Files/Common/` — see `news/sample_news_calendar.csv` for the
expected `yyyy.mm.dd HH:MM,CURRENCY,IMPORTANCE` format).

**"Lot size always computes to 0 / trade always rejected as 'below broker minimum'."**
This means `risk% × balance` divided by the ATR-based stop distance produces
less than one lot step at your broker's tick value for that symbol — usually
because the account balance is very small relative to the symbol's minimum
lot value. This is the system correctly refusing to round risk up rather
than a bug; either accept fewer symbols are tradeable at the current balance,
or (carefully, understanding the tradeoff) raise `InpRiskPercent` toward the
5% ceiling.

**"Reconnect handling — EA goes quiet after a dropped connection."**
`CTradeEngine::IsConnectionHealthy()` checks `TERMINAL_CONNECTED`,
`ACCOUNT_TRADE_ALLOWED`, and `TERMINAL_TRADE_ALLOWED` every tick and skips
trading (without erroring) until all three pass again. No action needed —
it resumes automatically once the terminal reconnects to the trade server.

## Python bridge

**"MetaTrader5 package fails to import / `initialize()` returns False."**
The `MetaTrader5` Python package only works on Windows (it wraps the native
MT5 terminal's IPC interface) and requires a matching MT5 terminal to be
installed and logged in on the same machine (or reachable via the terminal's
own server connection). It will not run on Linux/macOS without a Windows VM
or a Wine-based workaround — this is an MT5 platform limitation, not specific
to this bridge.

**"Bridge and EA both open positions for the same signal."**
Run only one execution path per account/magic-number. Both the EA and the
Python bridge implement the same confluence logic, so running both against
the same account will double the position size taken per signal.

**"`ComputeSupertrend`/Python `supertrend()` seems slow."**
Both are recomputed over a bounded lookback window on every call rather than
maintained incrementally. This is intentional for correctness/simplicity at
day-trading timeframes (M5–M30, a handful of symbols); it would need to move
to an incremental/streaming calculation if scaled to many more symbols or
sub-minute timeframes.

## General

**"Which module do I change to adjust X?"**
See `docs/ARCHITECTURE.md` — it maps every rule to the module that
implements it in all three platforms (Pine/MQL5/Python), so you're not
guessing which file to touch.
