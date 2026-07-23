//+------------------------------------------------------------------+
//|                                                       Types.mqh  |
//| Shared enums/structs for the A+ Confluence EA modules.           |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_TYPES_MQH
#define APC_TYPES_MQH

enum ENUM_TREND_BIAS
  {
   TREND_NEUTRAL = 0,
   TREND_BULLISH = 1,
   TREND_BEARISH = -1
  };

enum ENUM_STRUCTURE_BIAS
  {
   STRUCT_UNDEFINED = 0,
   STRUCT_BULLISH   = 1,  // HH/HL sequence
   STRUCT_BEARISH   = -1  // LH/LL sequence
  };

enum ENUM_SESSION
  {
   SESSION_NONE,
   SESSION_ASIAN,
   SESSION_LONDON,
   SESSION_NEWYORK,
   SESSION_OVERLAP
  };

// One resolved trade decision, produced by the signal/confluence engine and
// consumed by the trade engine. Keeping this as a single struct means the
// signal engine never has to know how orders get placed.
struct STradeSignal
  {
   bool              isValid;
   bool              isBuy;
   double            entry;
   double            stopLoss;
   double            takeProfit;
   double            partialTP;
   double            riskRewardRatio;
   double            lotSize;
   string            reason;
  };

// Symbol specification snapshot — pulled fresh per decision so the EA never
// hardcodes broker-specific contract details (required for Exness where
// digits/tick size/step vary per symbol and can change).
struct SSymbolSpec
  {
   string            symbol;
   int               digits;
   double            point;
   double            tickSize;
   double            tickValue;
   double            minLot;
   double            maxLot;
   double            lotStep;
   double            contractSize;
  };

// Rolling performance counters for the dashboard / journal — updated on
// every closed position, never recomputed from full history each tick.
struct SPerformanceStats
  {
   int               totalTrades;
   int               winTrades;
   int               lossTrades;
   double            grossProfit;
   double            grossLoss;
   double            largestWin;
   double            largestLoss;
   double            equityPeak;
   double            maxDrawdownPct;
  };

// Per-symbol persistent state. One instance lives in a global array for the
// whole EA lifetime — indicator handles are created once in OnInit and swing/
// order-block levels persist across ticks instead of being recomputed from
// scratch (recomputing from full history every tick is what makes naive EAs
// slow and prone to subtle repaint bugs).
struct SSymbolState
  {
   string            symbol;
   int               handleEmaFast;
   int               handleEmaMid;
   int               handleEmaSlow;
   int               handleAtr;
   int               handleRsi;
   int               handleMacd;
   int               handleAdx;

   double            lastSwingHigh;
   double            prevSwingHigh;
   double            lastSwingLow;
   double            prevSwingLow;
   int               lastHighType;   // 1 = HH, -1 = LH
   int               lastLowType;    // 1 = HL, -1 = LL
   ENUM_STRUCTURE_BIAS structureBias;

   double            bullOB_top;
   double            bullOB_bot;
   double            bearOB_top;
   double            bearOB_bot;
   double            bullFVG_top;
   double            bullFVG_bot;
   double            bearFVG_top;
   double            bearFVG_bot;

   datetime          lastSweepLowTime;
   datetime          lastSweepHighTime;
   datetime          lastBarTime;     // guards one-decision-per-closed-bar

   ulong             openTicket;      // 0 if flat
   bool              breakevenDone;
   bool              partialDone;
   datetime          entryTime;
   double            entrySL;
   double            entryTP;
   double            partialTP;
  };

#endif // APC_TYPES_MQH
