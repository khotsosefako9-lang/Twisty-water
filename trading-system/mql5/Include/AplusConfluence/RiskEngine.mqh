//+------------------------------------------------------------------+
//|                                                  RiskEngine.mqh  |
//| The single source of truth for "how many lots". Every other      |
//| module hands this engine a stop distance and gets back either a  |
//| broker-legal lot size or a rejection — it never rounds risk up.  |
//+------------------------------------------------------------------+
#property strict
#ifndef APC_RISKENGINE_MQH
#define APC_RISKENGINE_MQH
#include "Types.mqh"
#include "Utils.mqh"

input group "=== Risk Management ==="
input double InpRiskPercent        = 1.0;   // Risk % per trade (default)
input double InpMaxRiskPercent     = 5.0;   // Hard ceiling — never exceeded regardless of input above
input double InpMaxSpreadPoints    = 35;    // Reject trade if current spread exceeds this
input double InpMinAtrPercent      = 0.03;  // Reject trade if ATR% of price below this (dead market)
input double InpMaxAtrPercent      = 1.20;  // Reject trade if ATR% of price above this (abnormal spike)

class CRiskEngine
  {
private:
   double m_riskPercent;

public:
   void Init(void)
     {
      m_riskPercent = MathMin(InpRiskPercent, InpMaxRiskPercent);
      if(m_riskPercent <= 0)
         m_riskPercent = 1.0;
     }

   double RiskPercent(void) const { return m_riskPercent; }

   // Core position-sizing formula:
   //   lots = (balance * risk%) / (stopDistance_in_price * (tickValue / tickSize))
   // (tickValue / tickSize) converts a price-distance into "money per 1.0 lot per unit price",
   // which is the only broker-agnostic way to do this correctly across FX, metals and indices.
   double CalculateLotSize(const double balance, const double stopDistancePrice, const SSymbolSpec &spec, string &rejectReason)
     {
      rejectReason = "";
      if(stopDistancePrice <= 0)
        {
         rejectReason = "invalid stop distance";
         return 0.0;
        }

      double riskAmount = balance * (m_riskPercent / 100.0);
      double moneyPerUnitPricePerLot = SafeDivide(spec.tickValue, spec.tickSize, 0.0);
      if(moneyPerUnitPricePerLot <= 0)
        {
         rejectReason = "symbol tick value/size unavailable";
         return 0.0;
        }

      double rawLot = riskAmount / (stopDistancePrice * moneyPerUnitPricePerLot);
      double lot = NormalizeLotSize(rawLot, spec.minLot, spec.maxLot, spec.lotStep);

      if(lot <= 0)
        {
         rejectReason = "computed lot below broker minimum — risk% too small for this stop distance";
         return 0.0;
        }

      // Confirm actual monetary risk of the rounded lot never exceeds the cap due to rounding.
      double actualRisk = lot * stopDistancePrice * moneyPerUnitPricePerLot;
      double maxAllowedRisk = balance * (InpMaxRiskPercent / 100.0);
      if(actualRisk > maxAllowedRisk * 1.01) // 1% tolerance for lot-step rounding
        {
         rejectReason = "rounded lot would exceed max risk ceiling";
         return 0.0;
        }

      return lot;
     }

   bool ValidateSpread(const string symbol, string &rejectReason)
     {
      double spreadPoints = GetSpreadPoints(symbol);
      if(spreadPoints > InpMaxSpreadPoints)
        {
         rejectReason = StringFormat("spread %.1f pts exceeds max %.1f", spreadPoints, InpMaxSpreadPoints);
         return false;
        }
      return true;
     }

   bool ValidateVolatility(const double atrValue, const double price, string &rejectReason)
     {
      if(price <= 0)
        {
         rejectReason = "invalid price";
         return false;
        }
      double atrPct = (atrValue / price) * 100.0;
      if(atrPct < InpMinAtrPercent)
        {
         rejectReason = StringFormat("ATR%% %.4f below min %.4f (dead market)", atrPct, InpMinAtrPercent);
         return false;
        }
      if(atrPct > InpMaxAtrPercent)
        {
         rejectReason = StringFormat("ATR%% %.4f above max %.4f (abnormal spike)", atrPct, InpMaxAtrPercent);
         return false;
        }
      return true;
     }
  };

#endif // APC_RISKENGINE_MQH
