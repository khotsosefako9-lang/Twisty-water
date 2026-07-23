//+------------------------------------------------------------------+
//|                                                  Indicators.mqh  |
//| Indicator handle lifecycle + the two indicators MT5 has no native |
//| handle for (session VWAP, Supertrend) computed manually.          |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_INDICATORS_MQH
#define APC_INDICATORS_MQH
#include "Types.mqh"

input group "=== Trend / Momentum Indicators ==="
input int    InpEmaFastLen   = 20;
input int    InpEmaMidLen    = 50;
input int    InpEmaSlowLen   = 200;
input int    InpAtrLen       = 14;
input int    InpRsiLen       = 14;
input int    InpMacdFast     = 12;
input int    InpMacdSlow     = 26;
input int    InpMacdSignal   = 9;
input int    InpAdxLen       = 14;
input double InpSupertrendFactor = 3.0;
input int    InpSupertrendAtrLen = 10;
input double InpRelVolThreshold  = 1.1;
input int    InpVolSmaLen        = 20;

bool CreateIndicatorHandles(SSymbolState &state, const ENUM_TIMEFRAMES tf)
  {
   state.handleEmaFast = iMA(state.symbol, tf, InpEmaFastLen, 0, MODE_EMA, PRICE_CLOSE);
   state.handleEmaMid  = iMA(state.symbol, tf, InpEmaMidLen, 0, MODE_EMA, PRICE_CLOSE);
   state.handleEmaSlow = iMA(state.symbol, tf, InpEmaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   state.handleAtr     = iATR(state.symbol, tf, InpAtrLen);
   state.handleRsi     = iRSI(state.symbol, tf, InpRsiLen, PRICE_CLOSE);
   state.handleMacd    = iMACD(state.symbol, tf, InpMacdFast, InpMacdSlow, InpMacdSignal, PRICE_CLOSE);
   state.handleAdx     = iADX(state.symbol, tf, InpAdxLen);

   return (state.handleEmaFast != INVALID_HANDLE && state.handleEmaMid != INVALID_HANDLE &&
           state.handleEmaSlow != INVALID_HANDLE && state.handleAtr != INVALID_HANDLE &&
           state.handleRsi != INVALID_HANDLE && state.handleMacd != INVALID_HANDLE &&
           state.handleAdx != INVALID_HANDLE);
  }

void ReleaseIndicatorHandles(SSymbolState &state)
  {
   if(state.handleEmaFast != INVALID_HANDLE) IndicatorRelease(state.handleEmaFast);
   if(state.handleEmaMid  != INVALID_HANDLE) IndicatorRelease(state.handleEmaMid);
   if(state.handleEmaSlow != INVALID_HANDLE) IndicatorRelease(state.handleEmaSlow);
   if(state.handleAtr     != INVALID_HANDLE) IndicatorRelease(state.handleAtr);
   if(state.handleRsi     != INVALID_HANDLE) IndicatorRelease(state.handleRsi);
   if(state.handleMacd    != INVALID_HANDLE) IndicatorRelease(state.handleMacd);
   if(state.handleAdx     != INVALID_HANDLE) IndicatorRelease(state.handleAdx);
  }

double GetBufferValue(const int handle, const int bufferIndex, const int shift)
  {
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(handle, bufferIndex, shift, 1, buf) <= 0)
      return EMPTY_VALUE;
   return buf[0];
  }

// Session-anchored VWAP: rebuilt from the start of the current broker trading
// day each call. Cheap enough at day-trading timeframes (M5-M30) and avoids
// having to maintain a running cumulative sum per symbol across restarts.
double ComputeSessionVWAP(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);

   MqlRates rates[];
   int copied = CopyRates(symbol, tf, dayStart, TimeCurrent(), rates);
   if(copied <= 0)
      return 0.0;

   double sumPV = 0.0, sumV = 0.0;
   for(int i = 0; i < copied; i++)
     {
      double typical = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      double vol = (double)(rates[i].tick_volume > 0 ? rates[i].tick_volume : rates[i].real_volume);
      sumPV += typical * vol;
      sumV  += vol;
     }
   return SafeDivide(sumPV, sumV, rates[copied - 1].close);
  }

// Manual Supertrend — MT5 has no built-in handle for it. Rebuilt over a
// bounded lookback each call; returns [0]=value, [1]=direction(-1 up, 1 down).
void ComputeSupertrend(const string symbol, const ENUM_TIMEFRAMES tf, const double factor,
                        const int atrLen, const int lookback, double &outValue, int &outDirection)
  {
   MqlRates rates[];
   int copied = CopyRates(symbol, tf, 0, lookback, rates);
   if(copied < atrLen + 2)
     {
      outValue = 0.0;
      outDirection = 0;
      return;
     }
   ArraySetAsSeries(rates, false); // oldest -> newest, matches the iterative recurrence below

   double atr[];
   ArrayResize(atr, copied);
   for(int i = 0; i < copied; i++)
     {
      if(i == 0) { atr[i] = rates[i].high - rates[i].low; continue; }
      double tr = MathMax(rates[i].high - rates[i].low,
                  MathMax(MathAbs(rates[i].high - rates[i - 1].close), MathAbs(rates[i].low - rates[i - 1].close)));
      atr[i] = (atr[i - 1] * (atrLen - 1) + tr) / atrLen;
     }

   double finalUpper = 0, finalLower = 0, superTrend = 0;
   int direction = -1; // -1 = uptrend, 1 = downtrend (matches Pine convention used in the strategy)

   for(int i = 1; i < copied; i++)
     {
      double mid = (rates[i].high + rates[i].low) / 2.0;
      double basicUpper = mid + factor * atr[i];
      double basicLower = mid - factor * atr[i];

      double prevFinalUpper = finalUpper;
      double prevFinalLower = finalLower;

      finalUpper = (basicUpper < prevFinalUpper || rates[i - 1].close > prevFinalUpper || i == 1) ? basicUpper : prevFinalUpper;
      finalLower = (basicLower > prevFinalLower || rates[i - 1].close < prevFinalLower || i == 1) ? basicLower : prevFinalLower;

      if(rates[i].close > finalUpper)
         direction = -1;
      else if(rates[i].close < finalLower)
         direction = 1;
      // else keep previous direction

      superTrend = (direction == -1) ? finalLower : finalUpper;
     }

   outValue = superTrend;
   outDirection = direction;
  }

double ComputeRelativeVolume(const string symbol, const ENUM_TIMEFRAMES tf, const int smaLen)
  {
   long volumes[];
   ArraySetAsSeries(volumes, true);
   if(CopyTickVolume(symbol, tf, 0, smaLen + 1, volumes) <= 0)
      return 0.0;

   double sum = 0;
   for(int i = 1; i <= smaLen; i++)
      sum += (double)volumes[i];
   double avg = sum / smaLen;
   return SafeDivide((double)volumes[0], avg, 0.0);
  }

#endif // APC_INDICATORS_MQH
