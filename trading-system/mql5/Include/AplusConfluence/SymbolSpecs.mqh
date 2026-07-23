//+------------------------------------------------------------------+
//|                                                 SymbolSpecs.mqh  |
//| Reads live broker contract specs so lot-sizing math never uses   |
//| hardcoded assumptions. Exness varies digits/tick size/step across |
//| symbols and can change them, so this is queried fresh, not cached |
//| at OnInit only.                                                   |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_SYMBOLSPECS_MQH
#define APC_SYMBOLSPECS_MQH
#include "Types.mqh"

bool GetSymbolSpec(const string symbol, SSymbolSpec &spec)
  {
   if(!SymbolSelect(symbol, true))
      return false;

   spec.symbol       = symbol;
   spec.digits       = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   spec.point        = SymbolInfoDouble(symbol, SYMBOL_POINT);
   spec.tickSize     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   spec.tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   spec.minLot       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   spec.maxLot       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   spec.lotStep      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   spec.contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   if(spec.tickSize <= 0 || spec.tickValue <= 0 || spec.lotStep <= 0)
      return false; // broker hasn't published usable specs — never guess these

   return true;
  }

double GetSpreadPoints(const string symbol)
  {
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0)
      return 0.0;
   return (ask - bid) / point;
  }

#endif // APC_SYMBOLSPECS_MQH
