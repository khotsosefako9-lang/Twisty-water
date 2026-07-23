# Risk Guidelines — Micro Account

These are the operating rules the system enforces in code. Read this before
connecting a funded account.

## Hard limits (enforced, not just suggested)

| Rule | Value | Enforced in |
|---|---|---|
| Default risk per trade | 1% | `RiskEngine.mqh` / `risk_engine.py` / Pine input default |
| Optional risk per trade | 2% | user-configurable input |
| **Maximum risk per trade** | **5%** | hard `MathMin`/`math.min` clamp — cannot be exceeded by input |
| Minimum Risk:Reward | 1:3 | trade rejected outright if structural RR < 3 |
| Maximum Risk:Reward target | 1:5 | capped even if structure allows more |
| Max holding time | 48 bars (configurable) | forced close, no overnight micro-account exposure by default |
| Max spread | 35 points (configurable) | trade rejected if exceeded |
| News blackout | ±30 min around high-impact events | trade rejected during window |

## Why 1% default on a micro account

A micro account's primary risk is **ruin from a losing streak**, not
under-earning. At 1% risk with a genuine 1:3+ RR edge and a win rate as low
as 30%, expectancy is still positive (`0.30 × 3R − 0.70 × 1R = +0.20R` per
trade) while a 10-trade losing streak only costs ~10% of the account —
recoverable. At 5% risk, the same losing streak costs ~40% (compounding
losses), which is a much harder hole to climb out of. **2% is offered as an
"optional aggressive" tier for accounts that have already built a buffer
above the original micro deposit — not a starting point.**

## Position sizing — how lots are actually computed

```
riskAmount   = balance × min(riskPercent, 5%)
moneyPerUnit = tickValue / tickSize        (symbol-specific, read live from broker)
rawLot       = riskAmount / (stopDistance × moneyPerUnit)
lot          = floor(rawLot / lotStep) × lotStep     — rounded DOWN, clamped to [minLot, maxLot]
```

If the computed lot rounds down to below the broker's minimum lot, **the
trade is rejected**, not floored up to the minimum — taking the minimum lot
in that case would exceed the configured risk%.

## Trade rejection conditions (all objective, all logged)

- Risk% would exceed the 5% ceiling after rounding
- Computed lot size is below the broker's minimum tradeable lot
- Spread exceeds the configured maximum
- Slippage on order fill exceeds the configured deviation (MQL5 `CTrade`
  deviation parameter / Python `deviation` field on the trade request)
- A high-impact news event falls within the blackout window
- ATR% is below the "dead market" floor or above the "abnormal spike" ceiling
- Structural Risk:Reward is below 1:3
- A position is already open on that symbol (no pyramiding)
- Outside configured trading sessions, or Friday-late block is active

## Recommended account setup for Exness (ZAR)

- Use a **Standard** or **Zero** account type with Market Execution — the
  system assumes market orders with a `deviation`/slippage tolerance, not
  Instant Execution with requotes.
- Confirm **hedging vs netting** mode matches your `CTrade` expectations —
  this system opens one position per symbol at a time, so either mode works,
  but netting accounts will merge same-symbol positions if you also trade
  manually alongside the EA.
- Start on the smallest real-money deposit you're prepared to lose in full
  while validating live behavior against backtested/forward-tested
  expectations — no backtest guarantees live slippage, spread, or fill
  behavior on a micro account.

## What this system will not do

- It will not "make back" a losing streak by increasing size — risk% is
  fixed per trade regardless of recent results (no martingale, no
  revenge-sizing logic exists anywhere in the codebase).
- It will not override the session/news/volatility filters for a "good
  looking" setup — the filters are unconditional gates, not soft warnings.
- It will not run multiple concurrent positions on the same symbol.
