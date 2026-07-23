# Architecture & Design Decisions

This document explains **why** each rule exists, so the system can be
audited and tuned without guessing at intent. Every rule below is objective
— translatable into code with no discretionary judgment calls.

## 1. Why confluence, not a single indicator

A single indicator (e.g. "buy when RSI < 30") has no way to distinguish a
healthy pullback from a structural breakdown. Institutional systems stack
independent, weakly-correlated confirmations so that a false signal in one
layer (say, momentum) is caught by another (say, structure or liquidity).
The cost is fewer trades — that is intentional. A micro account cannot
survive overtrading; consistency beats frequency.

## 2. Trend detection — why this specific stack

| Component | Role | Why this one |
|---|---|---|
| EMA 20/50/200 ribbon | Directional bias | Alignment (20>50>200 or reverse) is a simple, objective proxy for "the market is actually trending across three horizons," not just short-term noise. |
| Session VWAP | Intraday fair value | Price above/below VWAP tells you which side institutions are net positioned on *today* — critical for day trading, irrelevant for swing systems. |
| Supertrend(10,3) | Binary flip + trailing stop | Cheap to compute, gives a hard up/down flag, and doubles as the trailing-stop mechanism post-breakeven so the trend filter and the exit logic use the same source of truth. |
| ADX(14) > 20 | Regime filter | This is what "avoid ranging markets" means concretely: ADX below threshold = chop, and every other confirmation is unreliable in chop. This is evaluated first because it is the cheapest possible early-reject. |

All four must agree. This is deliberately strict — the point is to trade
rarely and only in a clear regime.

## 3. Market structure — HH/HL/LH/LL, BOS, CHOCH

Swing points are detected via **fractal pivots**: a high/low is only
confirmed once `pivotRight` bars have closed on either side of it. This is
what makes the system non-repainting — a pivot's value never changes once
printed, it is just known a few bars later than it formed. Trading off it
sooner would require future information (lookahead), which is explicitly
disallowed.

- **HH/HL** (higher high, higher low) → bullish structure.
- **LH/LL** (lower high, lower low) → bearish structure.
- **BOS** (Break of Structure): price closes beyond the most recent
  same-direction swing level → continuation confirmed.
- **CHOCH** (Change of Character): price closes beyond the most recent
  *opposite*-direction swing level while the prevailing bias still says
  otherwise → early reversal warning. The system does not enter on CHOCH
  alone; it invalidates stale bias and waits for a fresh HH/HL or LH/LL
  sequence to re-establish before trading the new direction.

## 4. Smart Money Concepts — where, not whether

Trend + structure answer "which direction." SMC answers "at what price."

- **Order Block**: the last opposite-colored candle immediately before the
  impulse that produced a BOS. Treated as the institutional entry footprint
  left behind on the way up/down.
- **Fair Value Gap**: classic 3-candle imbalance (`low[0] > high[2]` for
  bullish, `high[0] < low[2]` for bearish) — an unfilled gap that price
  statistically tends to revisit.
- **Mitigation**: price trading back into an OB/FVG for the first time,
  with the close still holding on the correct side (not fully invalidated).
- **Premium/Discount**: midpoint of the active swing range. Longs are only
  taken in the discount half (below midpoint), shorts only in the premium
  half (above midpoint). This is the rule that stops the system from buying
  strength late or selling weakness late — it is one of the more aggressive
  filters and will reject setups that "look" fine on trend/structure alone.

Both the Pine Script and the MQL5 EA track only the **most recent
unmitigated** OB/FVG per direction rather than a full multi-zone history —
a deliberate simplification. Multi-zone tracking adds bookkeeping complexity
without changing which trades qualify in the overwhelming majority of cases,
since the most recent zone is also the most structurally relevant one.

## 5. Liquidity sweeps (stop hunts)

A sweep = a wick pierces a prior swing high/low (where stop orders cluster)
and the same bar's close reclaims the other side. This is used as **evidence
of a stop hunt having already happened** — i.e. the "dumb money" stops have
already been run, making a reversal-continuation from here statistically
more likely than entering on a level with resting liquidity still intact.
The sweep must have occurred within `sweepLookback` bars (default 6) of the
signal bar — a stale sweep is not treated as still relevant.

Equal highs/equal lows (clusters within an ATR-scaled tolerance) are
computed and displayed as a confluence marker but are **not** a hard entry
gate — requiring both "equal" liquidity *and* a fresh sweep in the same
setup would make entries too rare to be practically useful. This tradeoff is
called out explicitly rather than hidden: it is the one place a strict
literal reading of "detect equal highs/equal lows" is relaxed to "sweep of a
swing level," which is the actionable form of the same concept.

## 6. Momentum & volume — confirmation, not triggers

RSI vs its 50 midline and MACD histogram slope must agree with the trade
direction, and relative volume must exceed 1.1x its 20-period average. None
of these can generate a signal alone — they only confirm or veto a setup
that has already passed trend/structure/zone/liquidity. This ordering
matters: cheap, coarse filters run first (trend, ADX), expensive/precise
ones (structure, zones, sweeps) run only if the coarse filters pass.

## 7. Volatility — ATR as the volatility governor

ATR expressed as a percentage of price (`ATR / close × 100`) drives three
separate decisions from one number:

1. **Trade filtering**: reject if ATR% is below a floor (spread would eat
   the edge in a dead market) or above a ceiling (abnormal spike / likely
   news-driven, unpredictable slippage).
2. **Stop-loss placement**: SL sits beyond the invalidation structure
   (order block / swing low) plus an ATR buffer, so the stop respects
   current volatility rather than a fixed pip count.
3. **Position sizing**: the wider the ATR-driven stop, the smaller the lot
   size, so monetary risk per trade stays constant regardless of which
   symbol or regime is trading.

## 8. Sessions — why London/NY/overlap, why not Asian by default

Day trading edges here depend on liquidity and volatility; Asian session
compresses both for the pairs and indices in scope (XAUUSD, EURUSD, GBPUSD,
NAS100, US30 all see their real volume in London/NY hours). Asian session
is blocked by default and only re-enabled if ATR% clears an explicit
override threshold — i.e. only if the Asian session is *unusually* active,
which is the exception, not the rule. Friday-late is blocked outright:
liquidity thins before the weekend and any position risks a weekend gap
with no way to react.

## 9. Risk management — the non-negotiable section

- **Position sizing formula** (identical across Pine/MQL5/Python):
  `lots = (balance × risk%) / (stopDistance × tickValue / tickSize)`.
  This is the only broker-agnostic way to convert a price-distance stop
  into a lot size that respects the *actual* monetary value of a price move
  for a given symbol — hardcoding "$10 per pip" assumptions breaks the
  moment you add a second symbol or the broker changes contract specs.
- **Hard 5% ceiling**: `risk%` is clamped to `min(input, 5%)` in every
  implementation, regardless of what a user configures. This is enforced
  in code, not just in documentation.
- **Round down, never up**: lot size is floored to the broker's lot step.
  Rounding up even one step can silently double intended risk on a small
  enough stop — unacceptable on a micro account where lot steps are a large
  fraction of typical position size.
- **Minimum 1:3 RR is a hard floor, not a target**: if the structural
  distance to the next liquidity level doesn't support at least 1:3, the
  trade is **rejected outright** — the system does not take a trade at a
  worse ratio just because everything else lined up. Reward is capped at
  1:5 (`finalRR = clamp(structuralRR, 3, 5)`) so a runaway structural target
  doesn't produce an unrealistic take-profit that price is unlikely to reach
  in a single day-trading session.

## 10. Exit logic

1. **Partial close at 1:2R** (50% by default) — locks in profit before the
   full target, which matters because day-trading targets extending to 1:5R
   will not always fill.
2. **Breakeven** the moment the partial target is hit — the runner can no
   longer turn into a loss.
3. **Supertrend trailing** on the runner once breakeven is secured — ties
   the exit mechanism back to the same trend indicator used for entry,
   rather than an unrelated fixed trailing distance.
4. **Time-based exit** (`maxHoldingBars`, default 48 bars) — enforces day
   trading discipline; a micro account cannot absorb multi-day adverse
   excursions on a position sized for an intraday stop.

## 11. Why the Pine Script and the MQL5 EA are kept logically identical

Both implement the same pivot, BOS/CHOCH, OB/FVG, sweep, and confluence
logic bar-for-bar wherever platform capability allows it (Pine's built-in
`ta.supertrend`/`ta.vwap`/`ta.pivothigh` map onto hand-rolled equivalents in
MQL5, since MT5 has no native handles for Supertrend or session VWAP). This
is deliberate: TradingView is used for visual analysis/backtesting, MT5 is
used for live execution, and if the two disagreed on what counts as a valid
setup, a trader cross-checking one against the other would lose confidence
in both.

## 12. News filtering — two different mechanisms, one intent

- **Pine Script** cannot reach an external economic calendar at all
  (TradingView's strategy/indicator sandbox has no such API) — it uses
  manually configured blackout time windows as a documented limitation.
- **MQL5** uses MT5's native `CalendarValueHistory()` Economic Calendar API
  first (no external dependency, no API key), with a CSV fallback for VPS
  setups where the terminal's calendar sync is unavailable.
- **Python** pulls the public ForexFactory weekly JSON calendar feed, since
  it has no equivalent to MT5's native calendar API.

All three enforce the same rule: no entries within a configurable window
(default 30 minutes) before or after a high-impact event for the currencies
relevant to the traded symbol.
