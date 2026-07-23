//+------------------------------------------------------------------+
//|                                                        Utils.mqh |
//| Small stateless helpers shared across modules.                   |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_UTILS_MQH
#define APC_UTILS_MQH

// Rounds a raw lot size down to the broker's lot step and clamps it inside
// [minLot, maxLot]. Rounding DOWN (never up) is deliberate: on a micro
// account, rounding up even one step can silently double the intended risk.
double NormalizeLotSize(const double rawLot, const double minLot, const double maxLot, const double lotStep)
  {
   if(lotStep <= 0)
      return 0.0;
   double steps = MathFloor(rawLot / lotStep);
   double lot = steps * lotStep;
   if(lot < minLot)
      return 0.0; // caller must treat 0 as "risk too small to express as a lot — reject the trade"
   if(lot > maxLot)
      lot = maxLot;
   return NormalizeDouble(lot, 2);
  }

double PointsBetween(const double priceA, const double priceB, const double point)
  {
   if(point <= 0)
      return 0.0;
   return MathAbs(priceA - priceB) / point;
  }

// Extracts a comma-separated watchlist input ("XAUUSD,EURUSD,GBPUSD") into an array.
int ParseSymbolList(const string csv, string &out[])
  {
   int count = StringSplit(csv, ',', out);
   for(int i = 0; i < count; i++)
     {
      StringTrimLeft(out[i]);
      StringTrimRight(out[i]);
     }
   return count;
  }

int FindSymbolIndex(const string &symbols[], const int count, const string symbol)
  {
   for(int i = 0; i < count; i++)
      if(symbols[i] == symbol)
         return i;
   return -1;
  }

double SafeDivide(const double numerator, const double denominator, const double fallback = 0.0)
  {
   if(MathAbs(denominator) < 0.0000001)
      return fallback;
   return numerator / denominator;
  }

#endif // APC_UTILS_MQH
