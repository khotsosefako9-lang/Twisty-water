//+------------------------------------------------------------------+
//|                                               SessionEngine.mqh  |
//| Session + calendar-time gating. All comparisons use broker server |
//| time shifted to UTC via InpBrokerGmtOffset, since Exness server   |
//| time is not UTC and shifts with DST on some server groups.        |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_SESSIONENGINE_MQH
#define APC_SESSIONENGINE_MQH
#include "Types.mqh"

input group "=== Sessions ==="
input int    InpBrokerGmtOffsetHours = 3;     // Broker server time minus UTC (check Exness server specs; typically UTC+2/UTC+3)
input bool   InpTradeLondon          = true;
input bool   InpTradeNewYork         = true;
input bool   InpTradeAsian           = false; // only honored if ATR% override triggers
input double InpAsianAtrOverridePct  = 0.50;
input bool   InpBlockFridayLate      = true;
input int    InpFridayLateHourUtc    = 18;

class CSessionEngine
  {
private:
   datetime NowUtc(void)
     {
      return TimeCurrent() - InpBrokerGmtOffsetHours * 3600;
     }

public:
   ENUM_SESSION CurrentSession(void)
     {
      MqlDateTime dt;
      TimeToStruct(NowUtc(), dt);
      int h = dt.hour;

      bool london = (h >= 7 && h < 16);
      bool newYork = (h >= 12 && h < 21);

      if(london && newYork)
         return SESSION_OVERLAP;
      if(london)
         return SESSION_LONDON;
      if(newYork)
         return SESSION_NEWYORK;
      if(h >= 23 || h < 7)
         return SESSION_ASIAN;
      return SESSION_NONE;
     }

   bool IsFridayLate(void)
     {
      if(!InpBlockFridayLate)
         return false;
      MqlDateTime dt;
      TimeToStruct(NowUtc(), dt);
      return (dt.day_of_week == 5 && dt.hour >= InpFridayLateHourUtc);
     }

   bool IsSessionAllowed(const double atrPct, string &rejectReason)
     {
      if(IsFridayLate())
        {
         rejectReason = "Friday late session blocked";
         return false;
        }

      ENUM_SESSION s = CurrentSession();
      switch(s)
        {
         case SESSION_OVERLAP:
            if(InpTradeLondon || InpTradeNewYork)
               return true;
            break;
         case SESSION_LONDON:
            if(InpTradeLondon)
               return true;
            break;
         case SESSION_NEWYORK:
            if(InpTradeNewYork)
               return true;
            break;
         case SESSION_ASIAN:
            if(InpTradeAsian && atrPct >= InpAsianAtrOverridePct)
               return true;
            rejectReason = "Asian session blocked (ATR% override not met)";
            return false;
         default:
            break;
        }
      rejectReason = "outside configured trading sessions";
      return false;
     }
  };

#endif // APC_SESSIONENGINE_MQH
