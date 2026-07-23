# A+ Confluence — Micro Day Trading System

Institutional-style, rule-based day trading system built for a **micro account** on
**Exness (ZAR account, MetaTrader 5)**, with a matching **TradingView Pine Script v6**
strategy for charting/backtesting and a **Python bridge** for automation/reporting.

Assets covered: **XAUUSD, EURUSD, GBPUSD, NAS100, US30**, and broker-listed
**Volatility Indexes** (wherever Exness lists them — confirm symbol names in
MT5 Market Watch, they vary by broker).

No discretion, no single-indicator entries. Every entry requires trend, market
structure, a Smart-Money-Concepts price zone, a liquidity sweep, momentum, and
volume to all agree, at a minimum 1:3 risk:reward — see `docs/ARCHITECTURE.md`
for the full rationale behind every rule.

## Structure

```
trading-system/
  pinescript/
    AplusConfluence_v6.pine        TradingView Pine Script v6 strategy
  mql5/
    Experts/AplusConfluenceEA.mq5  MetaTrader 5 Expert Advisor
    Include/AplusConfluence/       Modular EA logic (12 headers)
  python/
    main.py                       Bridge entry point (live loop + reporting)
    config.py, mt5_connector.py, risk_engine.py, session_engine.py,
    news_filter.py, indicators.py, signal_engine.py, trade_manager.py,
    performance_report.py
  news/
    sample_news_calendar.csv       Format reference for the MQL5 CSV news fallback
  docs/
    ARCHITECTURE.md                Design decisions, module by module
    RISK_GUIDELINES.md             Micro-account risk rules
    OPTIMIZATION.md                Suggested per-symbol/timeframe parameters
    TROUBLESHOOTING.md
```

## Quick start

### TradingView
1. Open `pinescript/AplusConfluence_v6.pine` in Pine Editor, add to chart.
2. Use the Strategy Tester tab for backtest stats (net profit, drawdown, win
   rate, trade list). Set `initial_capital` in the script to match your
   actual micro-account size before trusting the % numbers.
3. Right-click the chart → Add Alert → condition "A+ Confluence BUY/SELL" to
   get a notification (or webhook) on every valid signal.

### MetaTrader 5 (Exness)
1. Copy `mql5/Include/AplusConfluence/` to `MQL5/Include/AplusConfluence/` in
   your MT5 data folder (File → Open Data Folder).
2. Copy `mql5/Experts/AplusConfluenceEA.mq5` to `MQL5/Experts/`.
3. Compile in MetaEditor (F7). Fix any path issues if your broker's Include
   root differs.
4. Attach to any one chart (the EA loops over its own symbol watchlist
   internally — see `InpSymbolList`), enable AutoTrading.
5. See `docs/RISK_GUIDELINES.md` before going live with real money.

### Python bridge
```bash
cd python
pip install -r requirements.txt
cp .env.example .env   # create this yourself — see config.py for the variable names
python main.py          # live loop
python main.py report   # performance report + trade_log.csv export
```

Run **either** the MQL5 EA **or** the Python bridge per account/magic-number —
not both — or you will double-execute the same signals.

## Design summary

- **Trend**: EMA 20/50/200 ribbon + session VWAP + Supertrend(10,3) + ADX(14)>20.
- **Structure**: fractal swing pivots → HH/HL/LH/LL → BOS/CHOCH.
- **Entry zone**: Order Blocks + Fair Value Gaps, gated by Premium/Discount zoning.
- **Liquidity**: sweep of the prior swing high/low (stop-hunt) required before entry.
- **Confirmation**: RSI vs 50, MACD histogram slope, relative volume > 1.1x.
- **Risk**: 1% default / 5% hard ceiling, broker-tick-value-based lot sizing,
  minimum 1:3 RR (rejects the trade rather than taking a worse ratio),
  partial close at 1:2R, breakeven, Supertrend trailing, time-based exit.
- **Filters**: session (London/NY/overlap only by default), Friday-late block,
  high-impact news blackout, spread cap, ATR band (rejects dead and
  abnormally volatile conditions alike).

Full rationale for each of these: `docs/ARCHITECTURE.md`.
