//+------------------------------------------------------------------+
//|                                                   Dashboard.mqh  |
//| On-chart panel: trend, session, bias, ATR, spread, risk, lot,     |
//| today's P/L, open trades, win rate, drawdown, next high-impact    |
//| news. Pure presentation — reads state, never mutates it.          |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_DASHBOARD_MQH
#define APC_DASHBOARD_MQH
#include "Types.mqh"

input group "=== Dashboard ==="
input bool InpShowDashboard = true;
input int  InpDashboardX    = 10;
input int  InpDashboardY    = 20;

class CDashboard
  {
private:
   string m_prefix;
   int    m_lineHeight;

   void SetLabel(const string name, const string text, const int row, const color clr)
     {
      string objName = m_prefix + name;
      if(ObjectFind(0, objName) < 0)
        {
         ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, InpDashboardX);
         ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 9);
         ObjectSetString(0, objName, OBJPROP_FONT, "Consolas");
        }
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, InpDashboardY + row * m_lineHeight);
      ObjectSetString(0, objName, OBJPROP_TEXT, text);
      ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
     }

public:
   CDashboard(void) : m_prefix("APC_DASH_"), m_lineHeight(15) {}

   double ComputeTodaysProfit(const ulong magicNumber)
     {
      datetime dayStart = TimeCurrent() - (TimeCurrent() % 86400);
      double profit = 0;
      HistorySelect(dayStart, TimeCurrent());
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)magicNumber) continue;
         profit += HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
        }
      return profit;
     }

   void ComputeWinRate(const ulong magicNumber, double &winRatePct, int &totalClosed)
     {
      HistorySelect(0, TimeCurrent());
      int total = HistoryDealsTotal();
      int wins = 0, closedCount = 0;
      for(int i = 0; i < total; i++)
        {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)magicNumber) continue;
         if(HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         closedCount++;
         if(HistoryDealGetDouble(ticket, DEAL_PROFIT) > 0)
            wins++;
        }
      totalClosed = closedCount;
      winRatePct = closedCount > 0 ? (100.0 * wins / closedCount) : 0.0;
     }

   void Render(const string activeSymbol, const string trendLabel, const string sessionLabel,
               const string biasLabel, const double atrPct, const double spreadPoints,
               const double riskPercent, const double lotSize, const int openPositions,
               const string nextNewsLabel, const ulong magicNumber)
     {
      if(!InpShowDashboard)
         return;

      double todaysProfit = ComputeTodaysProfit(magicNumber);
      double winRate; int totalClosed;
      ComputeWinRate(magicNumber, winRate, totalClosed);

      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double drawdownPct = balance > 0 ? MathMax(0.0, (balance - equity) / balance * 100.0) : 0.0;

      int row = 0;
      SetLabel("title", "A+ Confluence — Micro Day Trader", row++, clrWhite);
      SetLabel("symbol", "Symbol: " + activeSymbol, row++, clrSilver);
      SetLabel("trend", "Trend: " + trendLabel, row++, trendLabel == "BULLISH" ? clrLime : (trendLabel == "BEARISH" ? clrTomato : clrSilver));
      SetLabel("bias", "Structure: " + biasLabel, row++, clrSilver);
      SetLabel("session", "Session: " + sessionLabel, row++, clrSilver);
      SetLabel("atr", "ATR%: " + DoubleToString(atrPct, 3), row++, clrSilver);
      SetLabel("spread", "Spread: " + DoubleToString(spreadPoints, 1) + " pts", row++, clrSilver);
      SetLabel("risk", "Risk: " + DoubleToString(riskPercent, 1) + "%  Lot: " + DoubleToString(lotSize, 2), row++, clrSilver);
      SetLabel("pnl", "Today's P/L: " + DoubleToString(todaysProfit, 2), row++, todaysProfit >= 0 ? clrLime : clrTomato);
      SetLabel("open", "Open Positions: " + IntegerToString(openPositions), row++, clrSilver);
      SetLabel("winrate", "Win Rate: " + DoubleToString(winRate, 1) + "% (" + IntegerToString(totalClosed) + " trades)", row++, clrSilver);
      SetLabel("dd", "Drawdown: " + DoubleToString(drawdownPct, 2) + "%", row++, drawdownPct > 5 ? clrTomato : clrSilver);
      SetLabel("news", "Next News: " + nextNewsLabel, row++, clrOrange);
     }

   void Remove(void)
     {
      ObjectsDeleteAll(0, m_prefix);
     }
  };

#endif // APC_DASHBOARD_MQH
