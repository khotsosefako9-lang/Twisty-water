//+------------------------------------------------------------------+
//|                                                  TradeEngine.mqh |
//| Order execution + open-position management: partial close,       |
//| breakeven, trailing stop, time-based exit, magic-number scoping,  |
//| retry-on-transient-error handling.                                 |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_TRADEENGINE_MQH
#define APC_TRADEENGINE_MQH
#include <Trade/Trade.mqh>
#include "Types.mqh"
#include "Logger.mqh"
#include "Indicators.mqh"

input group "=== Trade Execution ==="
input ulong  InpMagicNumber       = 20260723;
input int    InpSlippagePoints    = 20;
input int    InpMaxRetries        = 3;
input int    InpRetryDelayMs      = 500;
input int    InpMaxHoldingBars    = 48;
input double InpPartialRRMultiple = 2.0;
input double InpPartialClosePct   = 50.0;

class CTradeEngine
  {
private:
   CTrade   m_trade;
   CLogger *m_logger;

   bool IsRetryableError(const int retcode)
     {
      return(retcode == TRADE_RETCODE_REQUOTE || retcode == TRADE_RETCODE_PRICE_CHANGED ||
             retcode == TRADE_RETCODE_CONNECTION || retcode == TRADE_RETCODE_TIMEOUT ||
             retcode == TRADE_RETCODE_PRICE_OFF);
     }

public:
   void Init(CLogger *logger)
     {
      m_logger = logger;
      m_trade.SetExpertMagicNumber(InpMagicNumber);
      m_trade.SetDeviationInPoints(InpSlippagePoints);
      m_trade.SetTypeFillingBySymbol(_Symbol);
     }

   bool IsConnectionHealthy(void)
     {
      if(!TerminalInfoInteger(TERMINAL_CONNECTED))
        {
         m_logger.Warn("Terminal not connected to trade server — waiting for reconnect");
         return false;
        }
      if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
        {
         m_logger.Warn("Trading not allowed on this account (check AutoTrading / algo permissions)");
         return false;
        }
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        {
         m_logger.Warn("Algo trading disabled in terminal settings");
         return false;
        }
      return true;
     }

   // Opens a position, retrying transient broker-side errors. Rejections that
   // are NOT transient (invalid stops, no money, market closed) are logged
   // and NOT retried — retrying a structurally invalid order just spams the
   // trade server and can trigger broker throttling.
   bool OpenTrade(SSymbolState &state, const bool isBuy, const double lot, const double sl, const double tp,
                  const double partialTp, const string comment)
     {
      bool result = false;
      for(int attempt = 0; attempt < InpMaxRetries; attempt++)
        {
         result = isBuy ? m_trade.Buy(lot, state.symbol, 0.0, sl, tp, comment)
                        : m_trade.Sell(lot, state.symbol, 0.0, sl, tp, comment);

         if(result)
            break;

         int retcode = m_trade.ResultRetcode();
         m_logger.Error(StringFormat("%s order failed on %s: retcode=%d (%s)", isBuy ? "BUY" : "SELL",
                        state.symbol, retcode, m_trade.ResultRetcodeDescription()));

         if(!IsRetryableError(retcode))
            break;

         Sleep(InpRetryDelayMs);
        }

      if(result)
        {
         state.openTicket = m_trade.ResultOrder();
         state.entrySL = sl;
         state.entryTP = tp;
         state.partialTP = partialTp;
         state.entryTime = TimeCurrent();
         state.breakevenDone = false;
         state.partialDone = false;
         m_logger.Trade(StringFormat("%s %s lot=%.2f entry=%.5f sl=%.5f tp=%.5f partialTP=%.5f",
                        isBuy ? "BUY" : "SELL", state.symbol, lot, m_trade.ResultPrice(), sl, tp, partialTp));
        }
      return result;
     }

   // Called every tick for symbols that currently hold a position. Handles
   // the full lifecycle: partial close at the partial-R target, breakeven
   // stop move, ATR/Supertrend trailing on the runner, and the time-based
   // exit that enforces day-trading discipline on a micro account.
   void ManageOpenPosition(SSymbolState &state, const ENUM_TIMEFRAMES tf)
     {
      if(state.openTicket == 0)
         return;

      if(!PositionSelectByTicket(state.openTicket))
        {
         // Position closed externally (SL/TP hit, manual close) — reset state.
         state.openTicket = 0;
         return;
        }

      long posType = PositionGetInteger(POSITION_TYPE);
      bool isBuy = (posType == POSITION_TYPE_BUY);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = isBuy ? SymbolInfoDouble(state.symbol, SYMBOL_BID) : SymbolInfoDouble(state.symbol, SYMBOL_ASK);

      // --- Partial close at partial-R target ---
      bool partialHit = isBuy ? (currentPrice >= state.partialTP) : (currentPrice <= state.partialTP);
      if(!state.partialDone && partialHit)
        {
         double closeVolume = NormalizeDouble(volume * (InpPartialClosePct / 100.0), 2);
         double minLot = SymbolInfoDouble(state.symbol, SYMBOL_VOLUME_MIN);
         if(closeVolume >= minLot && closeVolume < volume)
           {
            if(m_trade.PositionClosePartial(state.openTicket, closeVolume))
              {
               state.partialDone = true;
               m_logger.Trade(StringFormat("Partial close %.2f lots on %s ticket=%d", closeVolume, state.symbol, state.openTicket));
              }
            else
               m_logger.Warn(StringFormat("Partial close failed on %s: %s", state.symbol, m_trade.ResultRetcodeDescription()));
           }
        }

      // --- Breakeven: after partial target reached, protect the runner at entry ---
      if(!state.breakevenDone && partialHit)
        {
         bool moved = isBuy ? m_trade.PositionModify(state.openTicket, openPrice, state.entryTP)
                            : m_trade.PositionModify(state.openTicket, openPrice, state.entryTP);
         if(moved)
           {
            state.breakevenDone = true;
            m_logger.Trade(StringFormat("Breakeven set on %s ticket=%d", state.symbol, state.openTicket));
           }
        }

      // --- Trailing stop via Supertrend once breakeven is secured ---
      if(state.breakevenDone)
        {
         double stValue; int stDir;
         ComputeSupertrend(state.symbol, tf, InpSupertrendFactor, InpSupertrendAtrLen, 200, stValue, stDir);
         double currentSL = PositionGetDouble(POSITION_SL);
         if(isBuy && stDir < 0 && stValue > currentSL && stValue < currentPrice)
            m_trade.PositionModify(state.openTicket, stValue, state.entryTP);
         else if(!isBuy && stDir > 0 && stValue < currentSL && stValue > currentPrice)
            m_trade.PositionModify(state.openTicket, stValue, state.entryTP);
        }

      // --- Time-based exit: day trading discipline, no overnight micro-account holds ---
      long barsHeld = (long)((TimeCurrent() - state.entryTime) / PeriodSeconds(tf));
      if(barsHeld >= InpMaxHoldingBars)
        {
         if(m_trade.PositionClose(state.openTicket))
           {
            m_logger.Trade(StringFormat("Time-based close on %s ticket=%d after %d bars", state.symbol, state.openTicket, barsHeld));
            state.openTicket = 0;
           }
        }
     }
  };

#endif // APC_TRADEENGINE_MQH
