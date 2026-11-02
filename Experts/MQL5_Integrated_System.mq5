//+------------------------------------------------------------------+
//|                                     MQL5_Integrated_System.mq5   |
//|                                  Copyright 2024, Trading AI User |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

// --- INPUTS ---
input int      Inp_MagicNum       = 123456;
input double   Inp_RiskPercent    = 1.0;    // Risk per trade (% of Equity)
input int      Inp_BarsToWait     = 5;      // Expiration in bars for limit orders
input double   Inp_BodyRatio      = 0.7;    // Minimum body/range ratio for breakout candles
input double   Inp_AtrMultiplier  = 1.5;    // Minimum ATR expansion factor
input int      Inp_LevelLookback  = 30;     // Significant level scan depth
input int      Inp_StopLossPips   = 250;    // Stop loss distance in points
input int      Inp_TakeProfitPips = 500;    // Take profit distance in points
input bool     Inp_UseTrailing    = true;   // Enable trailing stop logic
input double   Inp_TrailMult      = 2.5;    // ATR multiple for trailing stop distance

// --- GLOBALS ---
CTrade         m_trade;
int            hATR = INVALID_HANDLE;

int OnInit()
  {
   m_trade.SetExpertMagicNumber(Inp_MagicNum);

   // Initialize ATR handle once and reuse through CopyBuffer for performance and correctness.
   hATR = iATR(_Symbol, _Period, 14);
   if(hATR == INVALID_HANDLE)
     {
      Print(__FUNCTION__,": failed to create ATR handle");
      return(INIT_FAILED);
     }

   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(hATR != INVALID_HANDLE)
     {
      IndicatorRelease(hATR);
      hATR = INVALID_HANDLE;
     }
  }

void OnTick()
  {
   // 1) Only seek fresh entries when there is no open position for this EA on this symbol.
   if(!HasOpenPosition())
      CheckForSignals();

   // 2) Always manage existing positions/pending orders.
   ManageTrades();
  }

//+------------------------------------------------------------------+
//| STRATEGY FUNCTIONS                                                |
//+------------------------------------------------------------------+

// Significant Level Wick Rejection
int WickScoreAtLevel()
  {
   double h1 = iHigh(_Symbol, _Period, 1), l1 = iLow(_Symbol, _Period, 1);
   double o1 = iOpen(_Symbol, _Period, 1), c1 = iClose(_Symbol, _Period, 1);
   double range = h1 - l1;
   if(range <= 0)
      return 0;

   int hiBar = iHighest(_Symbol, _Period, MODE_HIGH, Inp_LevelLookback, 2);
   int loBar = iLowest(_Symbol, _Period, MODE_LOW, Inp_LevelLookback, 2);
   if(hiBar < 0 || loBar < 0)
      return 0;

   double sigHigh = iHigh(_Symbol, _Period, hiBar), sigLow = iLow(_Symbol, _Period, loBar);
   double currentATR = GetATR(1);
   if(currentATR <= 0.0)
      return 0;

   if(range < (Inp_AtrMultiplier * currentATR))
      return 0;

   double uWick = h1 - MathMax(o1, c1), lWick = MathMin(o1, c1) - l1;

   if(lWick/range >= 0.6 && l1 <= sigLow + (10 * _Point) && uWick/range <= 0.1)
      return 3;
   if(uWick/range >= 0.6 && h1 >= sigHigh - (10 * _Point) && lWick/range <= 0.1)
      return -3;
   return 0;
  }

// Trend Breakout Detection
int ImprovedTrendDirection()
  {
   int hiBar = iHighest(_Symbol, _Period, MODE_HIGH, 20, 2);
   int loBar = iLowest(_Symbol, _Period, MODE_LOW, 20, 2);
   if(hiBar < 0 || loBar < 0)
      return 0;

   double c1 = iClose(_Symbol, _Period, 1), o1 = iOpen(_Symbol, _Period, 1);
   double h1 = iHigh(_Symbol, _Period, 1), l1 = iLow(_Symbol, _Period, 1);
   double range = h1 - l1;
   if(range <= 0.0)
      return 0;

   // Use buffered ATR values (indicator handle), not iATR() direct-call style.
   double atrNow = GetATR(1);
   double atrAvg = GetATR(10);
   if(atrNow <= 0.0 || atrAvg <= 0.0)
      return 0;

   bool expansion = (atrNow > atrAvg * 1.2);
   bool solidBody = (MathAbs(c1-o1)/range >= Inp_BodyRatio);

   if(c1 > iHigh(_Symbol, _Period, hiBar) && solidBody && expansion)
      return 1;
   if(c1 < iLow(_Symbol, _Period, loBar)  && solidBody && expansion)
      return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| EXECUTION & MANAGEMENT                                            |
//+------------------------------------------------------------------+

// CTrade Execution
void ExecuteRetestEntry(bool isBuy)
  {
   double limitPrice = NormalizeDouble((iOpen(_Symbol, _Period, 1) + iClose(_Symbol, _Period, 1)) / 2.0, _Digits);
   double lot = CalculateLotSize(Inp_StopLossPips);
   if(lot <= 0.0)
      return;

   double sl = isBuy ? limitPrice - (Inp_StopLossPips * _Point) : limitPrice + (Inp_StopLossPips * _Point);
   double tp = isBuy ? limitPrice + (Inp_TakeProfitPips * _Point) : limitPrice - (Inp_TakeProfitPips * _Point);

   ENUM_ORDER_TYPE type = isBuy ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;

   // For limit orders: price=limitPrice, stoplimit=0.
   bool ok = m_trade.OrderOpen(_Symbol, type, lot, limitPrice, 0.0, sl, tp, ORDER_TIME_GTC, 0, "Retest-Entry");
   if(!ok)
      Print("OrderOpen failed. retcode=", m_trade.ResultRetcode(), " msg=", m_trade.ResultRetcodeDescription());
  }

// Comprehensive Management Loop
void ManageTrades()
  {
   // 1) Trail Active Positions
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNum || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(!Inp_UseTrailing)
         continue;

      double atr = GetATR(0);
      if(atr <= 0.0)
         continue;

      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
         double newSL = NormalizeDouble(bid - (atr * Inp_TrailMult), _Digits);
         if(newSL > PositionGetDouble(POSITION_SL) + (10 * _Point))
            m_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
      else
        {
         double newSL = NormalizeDouble(ask + (atr * Inp_TrailMult), _Digits);
         if(newSL < PositionGetDouble(POSITION_SL) - (10 * _Point) || PositionGetDouble(POSITION_SL) == 0)
            m_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
        }
     }

   // 2) Clean up old pending orders
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;

      if(!OrderSelect(ticket))
         continue;

      if(OrderGetInteger(ORDER_MAGIC) != Inp_MagicNum || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      int barsElapsed = iBarShift(_Symbol, _Period, setupTime);
      if(barsElapsed >= Inp_BarsToWait)
         m_trade.OrderDelete(ticket);
     }
  }

//+------------------------------------------------------------------+
//| UTILITY HELPERS                                                   |
//+------------------------------------------------------------------+

void CheckForSignals()
  {
   int wick = WickScoreAtLevel();
   if(wick != 0)
     {
      ExecuteRetestEntry(wick == 3);
      return;
     }

   int trend = ImprovedTrendDirection();
   if(trend != 0)
      ExecuteRetestEntry(trend == 1);
  }

double GetATR(int shift)
  {
   if(hATR == INVALID_HANDLE)
      return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(hATR, 0, shift, 1, buffer) > 0)
      return buffer[0];
   return 0.0;
  }

double CalculateLotSize(int slPoints)
  {
   double risk = AccountInfoDouble(ACCOUNT_EQUITY) * (Inp_RiskPercent / 100.0);
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   if(slPoints <= 0 || tickVal <= 0 || step <= 0)
      return minLot;

   double raw = risk / (slPoints * tickVal);
   double lot = MathFloor(raw / step) * step;
   if(lot < minLot)
      lot = minLot;
   return NormalizeDouble(lot, 2);
  }

bool HasOpenPosition()
  {
   for(int i=0; i<PositionsTotal(); i++)
     {
      string sym = PositionGetSymbol(i);
      if(sym == _Symbol && PositionGetInteger(POSITION_MAGIC) == Inp_MagicNum)
      return true;
     }
   return false;
   }

//+------------------------------------------------------------------+
double OnTester()
  {
   long trades=(long)TesterStatistics(STAT_TRADES);
   if(trades<30) return(0.0);
   double pf=TesterStatistics(STAT_PROFIT_FACTOR);
   if(pf<=0.0) return(0.0);
   double sharpe=TesterStatistics(STAT_SHARPE_RATIO);
   double recovery=TesterStatistics(STAT_RECOVERY_FACTOR);
   double profit=TesterStatistics(STAT_PROFIT);
   double expectancy=(trades>0) ? profit/trades : 0.0;
   double score=pf*MathMax(sharpe,0.0)*MathMax(recovery,0.0)*MathMax(expectancy,0.0)*MathSqrt(trades);
   return(score>0.0 ? score : 0.0);
  }
//+------------------------------------------------------------------+
