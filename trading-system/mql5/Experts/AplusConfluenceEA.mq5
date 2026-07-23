//+------------------------------------------------------------------+
//|                                        AplusConfluenceEA.mq5     |
//| A+ Confluence — Micro Day Trader                                 |
//| Multi-symbol, multi-confirmation day trading EA for Exness/MT5.  |
//| Mirrors the logic of AplusConfluence_v6.pine so TradingView       |
//| analysis and the live EA never disagree on what counts as a       |
//| valid setup.                                                       |
//|                                                                     |
//| Modules (Include/AplusConfluence/):                                |
//|   Types, Utils, Logger        - shared plumbing                    |
//|   SymbolSpecs, RiskEngine     - lot sizing / risk gating            |
//|   SessionEngine, NewsFilter   - time-based gating                  |
//|   Indicators                 - EMA/ATR/RSI/MACD/ADX + manual        |
//|                                 VWAP/Supertrend/RelVolume            |
//|   MarketStructure, SMC        - HH/HL/BOS/CHOCH, OB/FVG/zones        |
//|   TradeEngine                 - execution + position management      |
//|   Dashboard                   - on-chart panel                      |
//+------------------------------------------------------------------+
#property copyright "A+ Confluence"
#property version   "1.00"
#property strict

#include <AplusConfluence/Types.mqh>
#include <AplusConfluence/Utils.mqh>
#include <AplusConfluence/Logger.mqh>
#include <AplusConfluence/SymbolSpecs.mqh>
#include <AplusConfluence/RiskEngine.mqh>
#include <AplusConfluence/SessionEngine.mqh>
#include <AplusConfluence/NewsFilter.mqh>
#include <AplusConfluence/Indicators.mqh>
#include <AplusConfluence/MarketStructure.mqh>
#include <AplusConfluence/SMC.mqh>
#include <AplusConfluence/TradeEngine.mqh>
#include <AplusConfluence/Dashboard.mqh>

input group "=== Watchlist ==="
input string InpSymbolList = "XAUUSD,EURUSD,GBPUSD,NAS100,US30";
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15;

input group "=== Signal Thresholds ==="
input double InpAdxThreshold = 20.0;

CLogger       g_logger;
CRiskEngine   g_riskEngine;
CSessionEngine g_sessionEngine;
CNewsFilter   g_newsFilter;
CTradeEngine  g_tradeEngine;
CDashboard    g_dashboard;

SSymbolState  g_states[];
string        g_symbols[];
int           g_symbolCount = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_logger.Init("AplusConfluenceEA", true);
   g_riskEngine.Init();
   g_tradeEngine.Init(GetPointer(g_logger));

   g_symbolCount = ParseSymbolList(InpSymbolList, g_symbols);
   ArrayResize(g_states, g_symbolCount);

   for(int i = 0; i < g_symbolCount; i++)
     {
      g_states[i].symbol = g_symbols[i];
      if(!SymbolSelect(g_symbols[i], true))
        {
         g_logger.Error("Symbol not available on this broker: " + g_symbols[i]);
         continue;
        }
      if(!CreateIndicatorHandles(g_states[i], InpTimeframe))
        {
         g_logger.Error("Failed to create indicator handles for " + g_symbols[i]);
         continue;
        }
      g_logger.Info("Initialized symbol state for " + g_symbols[i]);
     }

   EventSetTimer(5);
   g_logger.Info("A+ Confluence EA initialized. Watching " + IntegerToString(g_symbolCount) + " symbols on " + EnumToString(InpTimeframe));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i = 0; i < g_symbolCount; i++)
      ReleaseIndicatorHandles(g_states[i]);
   g_dashboard.Remove();
   g_logger.Info("EA deinitialized, reason=" + IntegerToString(reason));
   g_logger.Deinit();
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   RefreshDashboard();
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(!g_tradeEngine.IsConnectionHealthy())
      return;

   for(int i = 0; i < g_symbolCount; i++)
     {
      g_tradeEngine.ManageOpenPosition(g_states[i], InpTimeframe);

      datetime barTime = iTime(g_states[i].symbol, InpTimeframe, 0);
      if(barTime == g_states[i].lastBarTime)
         continue; // only evaluate signals once per closed bar — no intrabar noise trading

      g_states[i].lastBarTime = barTime;
      EvaluateAndTrade(g_states[i]);
     }
  }

//+------------------------------------------------------------------+
//| Core confluence evaluation for one symbol, one freshly closed bar |
//+------------------------------------------------------------------+
void EvaluateAndTrade(SSymbolState &state)
  {
   if(state.openTicket != 0)
      return; // one position per symbol at a time — no pyramiding on a micro account

   string symbol = state.symbol;
   ENUM_TIMEFRAMES tf = InpTimeframe;

   double closeArr[2], highArr[1], lowArr[1];
   ArraySetAsSeries(closeArr, true);
   ArraySetAsSeries(highArr, true);
   ArraySetAsSeries(lowArr, true);
   if(CopyClose(symbol, tf, 1, 2, closeArr) <= 0) return;
   if(CopyHigh(symbol, tf, 1, 1, highArr) <= 0) return;
   if(CopyLow(symbol, tf, 1, 1, lowArr) <= 0) return;

   double close = closeArr[0];
   double prevClose = closeArr[1];
   double high = highArr[0];
   double low = lowArr[0];

   // --- Structure update (pivots, HH/HL/LH/LL) ---
   UpdateMarketStructure(state, tf);
   bool bosUp = IsBOSUp(state, prevClose, close);
   bool bosDown = IsBOSDown(state, prevClose, close);
   UpdateOrderBlocks(state, tf, bosUp, bosDown);
   UpdateFairValueGaps(state, tf);
   UpdateLiquiditySweeps(state, high, low, close, state.lastBarTime);

   // --- Trend stack ---
   double emaFast = GetBufferValue(state.handleEmaFast, 0, 1);
   double emaMid  = GetBufferValue(state.handleEmaMid, 0, 1);
   double emaSlow = GetBufferValue(state.handleEmaSlow, 0, 1);
   double atrVal  = GetBufferValue(state.handleAtr, 0, 1);
   double adxVal  = GetBufferValue(state.handleAdx, 0, 1);
   double vwapVal = ComputeSessionVWAP(symbol, tf);
   double stValue; int stDir;
   ComputeSupertrend(symbol, tf, InpSupertrendFactor, InpSupertrendAtrLen, 200, stValue, stDir);

   if(emaFast == EMPTY_VALUE || emaMid == EMPTY_VALUE || emaSlow == EMPTY_VALUE || atrVal == EMPTY_VALUE || adxVal == EMPTY_VALUE)
      return;

   bool trendBull = close > vwapVal && emaFast > emaMid && emaMid > emaSlow && stDir < 0 && adxVal > InpAdxThreshold;
   bool trendBear = close < vwapVal && emaFast < emaMid && emaMid < emaSlow && stDir > 0 && adxVal > InpAdxThreshold;

   // --- Momentum / volume ---
   double rsiVal = GetBufferValue(state.handleRsi, 0, 1);
   double macdMain0 = GetBufferValue(state.handleMacd, 0, 1);
   double macdSignal0 = GetBufferValue(state.handleMacd, 1, 1);
   double macdMain1 = GetBufferValue(state.handleMacd, 0, 2);
   double macdSignal1 = GetBufferValue(state.handleMacd, 1, 2);
   double macdHist0 = macdMain0 - macdSignal0;
   double macdHist1 = macdMain1 - macdSignal1;

   bool momentumBull = rsiVal > 50 && macdHist0 > macdHist1;
   bool momentumBear = rsiVal < 50 && macdHist0 < macdHist1;

   double relVol = ComputeRelativeVolume(symbol, tf, InpVolSmaLen);
   bool volumeConfirm = relVol > InpRelVolThreshold;

   // --- Zones / liquidity ---
   bool zoneBull = IsPriceInBullZone(state, high, low, close);
   bool zoneBear = IsPriceInBearZone(state, high, low, close);
   bool sweepLowRecent = IsSweepLowRecent(state, state.lastBarTime, tf);
   bool sweepHighRecent = IsSweepHighRecent(state, state.lastBarTime, tf);
   bool discountOK = IsDiscountZone(state, close);
   bool premiumOK = IsPremiumZone(state, close);

   // --- Filters (each produces an explicit rejection reason for the journal) ---
   string rejectReason = "";
   bool volatilityOK = g_riskEngine.ValidateVolatility(atrVal, close, rejectReason);
   double atrPct = (atrVal / close) * 100.0;
   bool sessionOK = volatilityOK && g_sessionEngine.IsSessionAllowed(atrPct, rejectReason);
   bool spreadOK = sessionOK && g_riskEngine.ValidateSpread(symbol, rejectReason);
   bool newsOK = spreadOK && !g_newsFilter.IsBlackout(symbol, rejectReason);

   bool longSignal = trendBull && state.structureBias == STRUCT_BULLISH && zoneBull && sweepLowRecent &&
                      momentumBull && volumeConfirm && volatilityOK && sessionOK && spreadOK && newsOK && discountOK;

   bool shortSignal = trendBear && state.structureBias == STRUCT_BEARISH && zoneBear && sweepHighRecent &&
                       momentumBear && volumeConfirm && volatilityOK && sessionOK && spreadOK && newsOK && premiumOK;

   if(!longSignal && !shortSignal)
      return;

   SSymbolSpec spec;
   if(!GetSymbolSpec(symbol, spec))
     {
      g_logger.Warn("Could not read symbol spec for " + symbol + " — trade skipped");
      return;
     }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(longSignal)
     {
      double slPrice = (state.bullOB_bot > 0 ? MathMin(state.bullOB_bot, state.lastSwingLow) : state.lastSwingLow) - atrVal * 0.25;
      double slDist = close - slPrice;
      if(slDist <= 0 || state.lastSwingHigh <= 0) return;

      double structuralRR = (state.lastSwingHigh - close) / slDist;
      double finalRR = MathMax(3.0, MathMin(5.0, structuralRR));
      if(structuralRR < 3.0)
        {
         g_logger.Info(symbol + " long setup rejected: structural RR " + DoubleToString(structuralRR, 2) + " below 1:3 floor");
         return;
        }

      double tp = close + slDist * finalRR;
      double partialTp = close + slDist * InpPartialRRMultiple;

      string lotRejectReason = "";
      double lot = g_riskEngine.CalculateLotSize(balance, slDist, spec, lotRejectReason);
      if(lot <= 0)
        {
         g_logger.Info(symbol + " long setup rejected: " + lotRejectReason);
         return;
        }

      g_tradeEngine.OpenTrade(state, true, lot, slPrice, tp, partialTp, "APC-Long-RR" + DoubleToString(finalRR, 1));
     }
   else if(shortSignal)
     {
      double slPrice = (state.bearOB_top > 0 ? MathMax(state.bearOB_top, state.lastSwingHigh) : state.lastSwingHigh) + atrVal * 0.25;
      double slDist = slPrice - close;
      if(slDist <= 0 || state.lastSwingLow <= 0) return;

      double structuralRR = (close - state.lastSwingLow) / slDist;
      double finalRR = MathMax(3.0, MathMin(5.0, structuralRR));
      if(structuralRR < 3.0)
        {
         g_logger.Info(symbol + " short setup rejected: structural RR " + DoubleToString(structuralRR, 2) + " below 1:3 floor");
         return;
        }

      double tp = close - slDist * finalRR;
      double partialTp = close - slDist * InpPartialRRMultiple;

      string lotRejectReason = "";
      double lot = g_riskEngine.CalculateLotSize(balance, slDist, spec, lotRejectReason);
      if(lot <= 0)
        {
         g_logger.Info(symbol + " short setup rejected: " + lotRejectReason);
         return;
        }

      g_tradeEngine.OpenTrade(state, false, lot, slPrice, tp, partialTp, "APC-Short-RR" + DoubleToString(finalRR, 1));
     }
  }

//+------------------------------------------------------------------+
void RefreshDashboard()
  {
   if(g_symbolCount == 0)
      return;

   string activeSymbol = _Symbol;
   int idx = FindSymbolIndex(g_symbols, g_symbolCount, activeSymbol);
   if(idx < 0)
      idx = 0;

   SSymbolState state = g_states[idx];
   double atrVal = GetBufferValue(state.handleAtr, 0, 0);
   double close = SymbolInfoDouble(state.symbol, SYMBOL_BID);
   double atrPct = (close > 0 && atrVal != EMPTY_VALUE) ? (atrVal / close) * 100.0 : 0.0;
   double spreadPoints = GetSpreadPoints(state.symbol);

   string trendLabel = "NEUTRAL/RANGE";
   double emaFast = GetBufferValue(state.handleEmaFast, 0, 0);
   double emaMid  = GetBufferValue(state.handleEmaMid, 0, 0);
   double emaSlow = GetBufferValue(state.handleEmaSlow, 0, 0);
   if(emaFast > emaMid && emaMid > emaSlow) trendLabel = "BULLISH";
   else if(emaFast < emaMid && emaMid < emaSlow) trendLabel = "BEARISH";

   string sessionLabel;
   switch(g_sessionEngine.CurrentSession())
     {
      case SESSION_LONDON: sessionLabel = "London"; break;
      case SESSION_NEWYORK: sessionLabel = "New York"; break;
      case SESSION_OVERLAP: sessionLabel = "London/NY Overlap"; break;
      case SESSION_ASIAN: sessionLabel = "Asian"; break;
      default: sessionLabel = "Off-Session"; break;
     }

   string biasLabel = state.structureBias == STRUCT_BULLISH ? "HH/HL (Bullish)" :
                       state.structureBias == STRUCT_BEARISH ? "LH/LL (Bearish)" : "Undefined";

   int openPositions = 0;
   for(int i = 0; i < g_symbolCount; i++)
      if(g_states[i].openTicket != 0)
         openPositions++;

   string rejectReason = "";
   string nextNewsLabel = g_newsFilter.IsBlackout(state.symbol, rejectReason) ? "BLACKOUT ACTIVE" : "Clear";

   g_dashboard.Render(activeSymbol, trendLabel, sessionLabel, biasLabel, atrPct, spreadPoints,
                       g_riskEngine.RiskPercent(), 0.0, openPositions, nextNewsLabel, InpMagicNumber);
  }
//+------------------------------------------------------------------+
