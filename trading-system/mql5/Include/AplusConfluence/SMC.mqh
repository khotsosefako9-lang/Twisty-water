//+------------------------------------------------------------------+
//|                                                        SMC.mqh   |
//| Smart Money Concepts: Order Blocks, Fair Value Gaps, mitigation,  |
//| and premium/discount zoning. These are the "where to enter"       |
//| layer — MarketStructure.mqh answers "what direction", this        |
//| answers "at what price".                                          |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_SMC_MQH
#define APC_SMC_MQH
#include "Types.mqh"

input group "=== Smart Money Concepts ==="
input int InpOrderBlockScanBars = 15;

// On a bullish BOS, the order block is the last down-close candle before the
// impulse that broke structure — that candle is where institutional buy
// orders are presumed to sit, since price left it behind on the way up.
void UpdateOrderBlocks(SSymbolState &state, const ENUM_TIMEFRAMES tf, const bool bosUp, const bool bosDown)
  {
   if(!bosUp && !bosDown)
      return;

   int need = InpOrderBlockScanBars + 2;
   double opens[], highs[], lows[], closes[];
   ArraySetAsSeries(opens, true);
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);

   if(CopyOpen(state.symbol, tf, 0, need, opens) <= 0) return;
   if(CopyHigh(state.symbol, tf, 0, need, highs) <= 0) return;
   if(CopyLow(state.symbol, tf, 0, need, lows) <= 0) return;
   if(CopyClose(state.symbol, tf, 0, need, closes) <= 0) return;

   if(bosUp)
     {
      for(int i = 1; i <= InpOrderBlockScanBars; i++)
        {
         if(closes[i] < opens[i]) // down-close candle
           {
            state.bullOB_top = highs[i];
            state.bullOB_bot = lows[i];
            break;
           }
        }
     }

   if(bosDown)
     {
      for(int i = 1; i <= InpOrderBlockScanBars; i++)
        {
         if(closes[i] > opens[i]) // up-close candle
           {
            state.bearOB_top = highs[i];
            state.bearOB_bot = lows[i];
            break;
           }
        }
     }
  }

// Classic 3-candle imbalance: gap between candle[i-2] and candle[i] that
// candle[i-1]'s body never filled.
void UpdateFairValueGaps(SSymbolState &state, const ENUM_TIMEFRAMES tf)
  {
   double highs[3], lows[3];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   if(CopyHigh(state.symbol, tf, 0, 3, highs) <= 0) return;
   if(CopyLow(state.symbol, tf, 0, 3, lows) <= 0) return;

   // index 0 = current (just closed) bar, 1 = middle, 2 = oldest of the trio
   if(lows[0] > highs[2])
     {
      state.bullFVG_top = lows[0];
      state.bullFVG_bot = highs[2];
     }
   if(highs[0] < lows[2])
     {
      state.bearFVG_top = lows[2];
      state.bearFVG_bot = highs[0];
     }
  }

bool IsPriceInBullZone(const SSymbolState &state, const double high, const double low, const double close)
  {
   bool inOB = (state.bullOB_top > 0) && low <= state.bullOB_top && high >= state.bullOB_bot && close > state.bullOB_bot;
   bool inFVG = (state.bullFVG_top > 0) && low <= state.bullFVG_top && high >= state.bullFVG_bot && close > state.bullFVG_bot;
   return inOB || inFVG;
  }

bool IsPriceInBearZone(const SSymbolState &state, const double high, const double low, const double close)
  {
   bool inOB = (state.bearOB_top > 0) && high >= state.bearOB_bot && low <= state.bearOB_top && close < state.bearOB_top;
   bool inFVG = (state.bearFVG_top > 0) && high >= state.bearFVG_bot && low <= state.bearFVG_top && close < state.bearFVG_top;
   return inOB || inFVG;
  }

// Discount = lower half of the active swing range (favor longs).
// Premium = upper half (favor shorts). No trade taken against this zoning —
// it is what stops the system from buying strength / selling weakness late.
bool IsDiscountZone(const SSymbolState &state, const double close)
  {
   if(state.lastSwingHigh <= 0 || state.lastSwingLow <= 0)
      return false;
   double mid = (state.lastSwingHigh + state.lastSwingLow) / 2.0;
   return close < mid;
  }

bool IsPremiumZone(const SSymbolState &state, const double close)
  {
   if(state.lastSwingHigh <= 0 || state.lastSwingLow <= 0)
      return false;
   double mid = (state.lastSwingHigh + state.lastSwingLow) / 2.0;
   return close > mid;
  }

#endif // APC_SMC_MQH
