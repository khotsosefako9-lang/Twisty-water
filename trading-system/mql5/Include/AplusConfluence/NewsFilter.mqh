//+------------------------------------------------------------------+
//|                                                  NewsFilter.mqh  |
//| Blocks entries around high-impact news using MT5's native         |
//| Economic Calendar API (CalendarValueHistory) — no external feed   |
//| dependency required. Falls back to a manual CSV window list if    |
//| the terminal's calendar is unavailable (e.g. some VPS setups).    |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_NEWSFILTER_MQH
#define APC_NEWSFILTER_MQH

input group "=== News Filter ==="
input bool   InpNewsFilterEnabled     = true;
input int    InpNewsMinutesBefore     = 30;
input int    InpNewsMinutesAfter      = 30;
input bool   InpNewsHighImportanceOnly = true;
input string InpNewsCsvFallbackFile   = "news_calendar_fallback.csv"; // Files\ or Common\Files\, format: yyyy.mm.dd HH:MM,CURRENCY,IMPORTANCE

class CNewsFilter
  {
private:
   // "EURUSD" -> {"EUR","USD"}; "XAUUSD" -> {"XAU","USD"}; indices/synthetics -> {"USD"}
   int ExtractCurrencies(const string symbol, string &out[])
     {
      string s = symbol;
      if(StringLen(s) >= 6)
        {
         ArrayResize(out, 2);
         out[0] = StringSubstr(s, 0, 3);
         out[1] = StringSubstr(s, 3, 3);
         return 2;
        }
      ArrayResize(out, 1);
      out[0] = "USD";
      return 1;
     }

   bool CheckCalendar(const string currency, const datetime fromTime, const datetime toTime)
     {
      MqlCalendarValue values[];
      int count = CalendarValueHistory(values, fromTime, toTime, NULL, currency);
      if(count <= 0)
         return false;

      for(int i = 0; i < count; i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev))
            continue;
         if(InpNewsHighImportanceOnly && ev.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;
         return true;
        }
      return false;
     }

   bool CheckCsvFallback(const datetime nowTime)
     {
      if(!FileIsExist(InpNewsCsvFallbackFile, FILE_COMMON))
         return false;

      int handle = FileOpen(InpNewsCsvFallbackFile, FILE_READ | FILE_CSV | FILE_COMMON, ',');
      if(handle == INVALID_HANDLE)
         return false;

      bool blackout = false;
      while(!FileIsEnding(handle))
        {
         string timeStr = FileReadString(handle);
         if(timeStr == "")
            break;
         string currency = FileReadString(handle);
         string importance = FileReadString(handle);

         datetime eventTime = StringToTime(timeStr);
         if(eventTime <= 0)
            continue;

         long diffMinutes = (long)(nowTime - eventTime) / 60;
         if(diffMinutes >= -InpNewsMinutesBefore && diffMinutes <= InpNewsMinutesAfter)
           {
            if(!InpNewsHighImportanceOnly || importance == "HIGH")
              {
               blackout = true;
               break;
              }
           }
        }
      FileClose(handle);
      return blackout;
     }

public:
   bool IsBlackout(const string symbol, string &rejectReason)
     {
      if(!InpNewsFilterEnabled)
         return false;

      datetime nowTime = TimeGMT();
      datetime fromTime = nowTime - InpNewsMinutesBefore * 60;
      datetime toTime   = nowTime + InpNewsMinutesAfter * 60;

      string currencies[];
      int n = ExtractCurrencies(symbol, currencies);

      for(int i = 0; i < n; i++)
        {
         if(CheckCalendar(currencies[i], fromTime, toTime))
           {
            rejectReason = "high-impact news window for " + currencies[i];
            return true;
           }
        }

      if(CheckCsvFallback(nowTime))
        {
         rejectReason = "news blackout (CSV fallback calendar)";
         return true;
        }

      return false;
     }
  };

#endif // APC_NEWSFILTER_MQH
