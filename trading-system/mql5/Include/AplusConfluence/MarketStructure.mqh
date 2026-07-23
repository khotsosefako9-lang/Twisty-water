//+------------------------------------------------------------------+
//|                                             MarketStructure.mqh  |
//| Fractal swing pivots -> HH/HL/LH/LL classification -> BOS/CHOCH.  |
//| Mirrors the Pine Script pivot logic bar-for-bar so both platforms |
//| agree on structure, which matters when TradingView is used for   |
//| discretionary confirmation alongside the live MT5 EA.             |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_MARKETSTRUCTURE_MQH
#define APC_MARKETSTRUCTURE_MQH
#include "Types.mqh"

input group "=== Market Structure / Liquidity ==="
input int    InpPivotLeft         = 5;
input int    InpPivotRight        = 5;
input int    InpSweepLookbackBars = 6;
input double InpEqualTolAtrMult   = 0.15;

// Returns true if the bar at "shift" (in a normal, non-series indexed array
// where index 0 = oldest) is a confirmed pivot high/low with InpPivotLeft/
// InpPivotRight bars of confirmation on each side.
bool IsPivotHigh(const double &highs[], const int idx, const int left, const int right, const int total)
  {
   if(idx - left < 0 || idx + right >= total)
      return false;
   double centerVal = highs[idx];
   for(int i = idx - left; i <= idx + right; i++)
     {
      if(i == idx)
         continue;
      if(highs[i] >= centerVal)
         return false;
     }
   return true;
  }

bool IsPivotLow(const double &lows[], const int idx, const int left, const int right, const int total)
  {
   if(idx - left < 0 || idx + right >= total)
      return false;
   double centerVal = lows[idx];
   for(int i = idx - left; i <= idx + right; i++)
     {
      if(i == idx)
         continue;
      if(lows[i] <= centerVal)
         return false;
     }
   return true;
  }

// Call once per new closed bar. Scans the most recently *confirmable* pivot
// (i.e. InpPivotRight bars back from the newest closed bar) and, if found,
// updates the persistent swing/structure state for this symbol.
void UpdateMarketStructure(SSymbolState &state, const ENUM_TIMEFRAMES tf)
  {
   int total = InpPivotLeft + InpPivotRight + 5;
   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, false);
   ArraySetAsSeries(lows, false);
   ArraySetAsSeries(closes, false);

   if(CopyHigh(state.symbol, tf, 0, total, highs) <= 0) return;
   if(CopyLow(state.symbol, tf, 0, total, lows) <= 0) return;
   if(CopyClose(state.symbol, tf, 0, total, closes) <= 0) return;

   int n = ArraySize(highs);
   int pivotIdx = n - 1 - InpPivotRight; // the bar that can now be confirmed as a pivot

   if(pivotIdx < InpPivotLeft)
      return;

   if(IsPivotHigh(highs, pivotIdx, InpPivotLeft, InpPivotRight, n))
     {
      double ph = highs[pivotIdx];
      state.lastHighType = (state.prevSwingHigh == 0) ? 1 : (ph > state.prevSwingHigh ? 1 : -1);
      state.prevSwingHigh = state.lastSwingHigh;
      state.lastSwingHigh = ph;
     }

   if(IsPivotLow(lows, pivotIdx, InpPivotLeft, InpPivotRight, n))
     {
      double pl = lows[pivotIdx];
      state.lastLowType = (state.prevSwingLow == 0) ? 1 : (pl > state.prevSwingLow ? 1 : -1);
      state.prevSwingLow = state.lastSwingLow;
      state.lastSwingLow = pl;
     }

   if(state.lastHighType == 1 && state.lastLowType == 1)
      state.structureBias = STRUCT_BULLISH;
   else if(state.lastHighType == -1 && state.lastLowType == -1)
      state.structureBias = STRUCT_BEARISH;
   else
      state.structureBias = STRUCT_UNDEFINED;
  }

bool IsBOSUp(const SSymbolState &state, const double prevClose, const double currClose)
  {
   return (state.lastSwingHigh > 0) && prevClose <= state.lastSwingHigh && currClose > state.lastSwingHigh;
  }

bool IsBOSDown(const SSymbolState &state, const double prevClose, const double currClose)
  {
   return (state.lastSwingLow > 0) && prevClose >= state.lastSwingLow && currClose < state.lastSwingLow;
  }

bool IsCHOCHBull(const SSymbolState &state, const bool bosUp) { return bosUp && state.structureBias == STRUCT_BEARISH; }
bool IsCHOCHBear(const SSymbolState &state, const bool bosDown) { return bosDown && state.structureBias == STRUCT_BULLISH; }

bool IsEqualHighs(const SSymbolState &state, const double atrValue)
  {
   if(state.prevSwingHigh <= 0)
      return false;
   return MathAbs(state.lastSwingHigh - state.prevSwingHigh) <= atrValue * InpEqualTolAtrMult;
  }

bool IsEqualLows(const SSymbolState &state, const double atrValue)
  {
   if(state.prevSwingLow <= 0)
      return false;
   return MathAbs(state.lastSwingLow - state.prevSwingLow) <= atrValue * InpEqualTolAtrMult;
  }

// Liquidity sweep = stop hunt: wick pierces the resting swing level, close
// reclaims the other side, on THIS closed bar. Timestamps let the signal
// engine require the sweep to have happened within InpSweepLookbackBars.
void UpdateLiquiditySweeps(SSymbolState &state, const double high, const double low, const double close, const datetime barTime)
  {
   if(state.lastSwingLow > 0 && low < state.lastSwingLow && close > state.lastSwingLow)
      state.lastSweepLowTime = barTime;
   if(state.lastSwingHigh > 0 && high > state.lastSwingHigh && close < state.lastSwingHigh)
      state.lastSweepHighTime = barTime;
  }

bool IsSweepLowRecent(const SSymbolState &state, const datetime currentBarTime, const ENUM_TIMEFRAMES tf)
  {
   if(state.lastSweepLowTime == 0)
      return false;
   long barsElapsed = (long)((currentBarTime - state.lastSweepLowTime) / PeriodSeconds(tf));
   return barsElapsed >= 0 && barsElapsed <= InpSweepLookbackBars;
  }

bool IsSweepHighRecent(const SSymbolState &state, const datetime currentBarTime, const ENUM_TIMEFRAMES tf)
  {
   if(state.lastSweepHighTime == 0)
      return false;
   long barsElapsed = (long)((currentBarTime - state.lastSweepHighTime) / PeriodSeconds(tf));
   return barsElapsed >= 0 && barsElapsed <= InpSweepLookbackBars;
  }

#endif // APC_MARKETSTRUCTURE_MQH
