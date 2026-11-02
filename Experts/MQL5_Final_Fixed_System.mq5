//+------------------------------------------------------------------+
//|                                     MQL5_Final_Fixed_System.mq5  |
//|                                  Copyright 2024, Trading AI User |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| INPUTS                                                            |
//+------------------------------------------------------------------+
input group "Core"
input int      Inp_MagicNum         = 123456;       // Magic number
input double   Inp_RiskPercent      = 1.0;          // Risk per trade, % of equity
input bool     Inp_AllowMinLotFloor = false;        // Floor to min lot instead of skipping (small accounts)
input int      Inp_BarsToWait       = 5;            // Bars until unfilled order is deleted

input group "Signals"
input double   Inp_BodyRatio        = 0.7;          // Min body/range ratio for trend candle
input double   Inp_AtrMultiplier    = 1.5;          // Min signal bar range (x ATR)
input int      Inp_LevelLookback    = 30;           // Support/resistance lookback (bars)
input double   Inp_LevelTolATR      = 0.1;          // Level touch tolerance (x ATR)
input int      Inp_TrendLookback    = 20;           // Trend breakout lookback (bars)
input double   Inp_ExpansionFactor  = 1.2;          // ATR expansion factor vs average
input int      Inp_ATRAvgPeriod     = 50;           // ATR average lookback for expansion

input group "Entry filters"
input bool             Inp_UseHTFFilter    = true;  // Use higher-timeframe EMA trend filter
input ENUM_TIMEFRAMES  Inp_HTF             = PERIOD_H4; // Higher timeframe for trend filter
input int              Inp_HTF_EMA_Period  = 200;   // HTF EMA period
input int              Inp_MaxSpreadPoints = 0;     // Max spread for entry, points (0 = off)
input int              Inp_SessionStartHour = 0;    // Session start hour, server time (0-23)
input int              Inp_SessionEndHour   = 24;   // Session end hour, server time (1-24; 0-24 = off)

input group "Stop loss / take profit"
input bool   Inp_UseATR_SLTP = true;    // ATR-based SL/TP (off = fixed points)
input double Inp_SL_ATRMult  = 2.0;      // Stop loss (x ATR)
input double Inp_TP_ATRMult  = 4.0;      // Take profit (x ATR)
input int    Inp_SL_Points   = 250;      // Fixed SL points (used when ATR mode off)
input int    Inp_TP_Points   = 500;      // Fixed TP points (used when ATR mode off)

input group "Trade management"
input bool   Inp_UseTrailing       = true;  // Use ATR trailing stop
input double Inp_TrailMult         = 2.5;   // Trailing distance (x ATR)
input double Inp_TrailStepATR      = 0.25;  // Min trailing improvement (x ATR)
input bool   Inp_UseBE             = true;  // Move stop to breakeven in profit
input double Inp_BE_TriggerATR     = 1.0;   // Breakeven trigger (x ATR in profit)
input int    Inp_BE_BufferPoints   = 10;    // Breakeven buffer from entry, points
input int    Inp_FridayCleanupHour = 20;    // Delete pending orders Friday from this hour (-1 = off)

input group "Optimization"
input double Inp_MaxDDPercent      = 20.0;  // Max equity drawdown % allowed by OnTester
input int    Inp_MinTradesForScore = 30;    // Min trades for OnTester to score a run

//+------------------------------------------------------------------+
//| GLOBALS                                                           |
//+------------------------------------------------------------------+
CTrade   m_trade;
int      hATR        = INVALID_HANDLE;
int      hHTFEMA     = INVALID_HANDLE;
datetime g_lastBarTime = 0;

// Forward declarations
void     CheckForSignals();
int      WickScoreAtLevel();
int      ImprovedTrendDirection();
bool     IsWithinSession();
bool     HTFTrendAllows(bool isBuy);
void     ExecuteRetestEntry(bool isBuy);
bool     ValidateLimitOrder(bool isBuy, double price, double sl, double tp);
double   GetATR_Val(int shift);
double   GetATRAvg(int period);
double   CalculateLotSize(int slPoints);
int      VolumeDigits(double step);
bool     IsNewBar();
bool     HasOpenPosition();
bool     HasOpenOrder();
void     ManageTrades();
void     ManagePositions();
void     ManagePendingOrders();
void     ModifyPosition(ulong ticket, double sl, double tp);

//+------------------------------------------------------------------+
//| INITIALIZATION                                                    |
//+------------------------------------------------------------------+
int OnInit()
  {
   m_trade.SetExpertMagicNumber(Inp_MagicNum);
   if(!m_trade.SetTypeFillingBySymbol(_Symbol))
      Print("Warning: could not set filling mode for ", _Symbol, ", error ", GetLastError());

   hATR = iATR(_Symbol, _Period, 14);
   if(hATR == INVALID_HANDLE)
     {
      Print("Failed to create ATR handle!");
      return(INIT_FAILED);
     }

   hHTFEMA = iMA(_Symbol, Inp_HTF, Inp_HTF_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(hHTFEMA == INVALID_HANDLE)
     {
      if(Inp_UseHTFFilter)
        {
         Print("Failed to create HTF EMA handle while HTF filter is enabled!");
         return(INIT_FAILED);
        }
      Print("Warning: HTF EMA handle failed (filter disabled, continuing).");
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hATR != INVALID_HANDLE)
      IndicatorRelease(hATR);
   if(hHTFEMA != INVALID_HANDLE)
      IndicatorRelease(hHTFEMA);
  }

//+------------------------------------------------------------------+
//| MAIN TICK                                                         |
//+------------------------------------------------------------------+
void OnTick()
  {
   ManageTrades();

   // Signals are evaluated once per new bar, and only when
   // neither an open position nor a pending order exists.
   if(IsNewBar() && !HasOpenPosition() && !HasOpenOrder())
      CheckForSignals();
  }

//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == 0 || t == g_lastBarTime)
      return false;
   g_lastBarTime = t;
   return true;
  }

//+------------------------------------------------------------------+
//| SIGNAL FUNCTIONS                                                  |
//+------------------------------------------------------------------+
void CheckForSignals()
  {
   int wick  = WickScoreAtLevel();
   int trend = (wick != 0) ? 0 : ImprovedTrendDirection();
   if(wick == 0 && trend == 0)
      return;

   bool   isBuy = (wick != 0) ? (wick == 3) : (trend == 1);
   string src   = (wick != 0) ? "Wick" : "Trend";

   // --- entry filters (only evaluated once a signal exists) ---
   if(Inp_MaxSpreadPoints > 0)
     {
      long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      if(spread > Inp_MaxSpreadPoints)
        {
         Print(src, " signal skipped: spread ", spread, " > max ", Inp_MaxSpreadPoints, " points");
         return;
        }
     }

   if(!IsWithinSession())
     {
      Print(src, " signal skipped: outside trading session");
      return;
     }

   if(!HTFTrendAllows(isBuy))
     {
      Print(src, " signal filtered by higher-timeframe trend");
      return;
     }

   Print(src, " Signal Detected: ", (isBuy ? "BUY" : "SELL"));
   ExecuteRetestEntry(isBuy);
  }

//+------------------------------------------------------------------+
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

   double sigHigh = iHigh(_Symbol, _Period, hiBar);
   double sigLow  = iLow(_Symbol, _Period, loBar);
   double currentATR = GetATR_Val(1);
   if(currentATR <= 0.0)
      return 0;

   if(range < (Inp_AtrMultiplier * currentATR))
      return 0;

   double uWick = h1 - MathMax(o1, c1), lWick = MathMin(o1, c1) - l1;
   double tol = Inp_LevelTolATR * currentATR;

   if(lWick/range >= 0.6 && l1 <= sigLow + tol && uWick/range <= 0.1) return 3;
   if(uWick/range >= 0.6 && h1 >= sigHigh - tol && lWick/range <= 0.1) return -3;
   return 0;
  }

//+------------------------------------------------------------------+
int ImprovedTrendDirection()
  {
   int hiBar = iHighest(_Symbol, _Period, MODE_HIGH, Inp_TrendLookback, 2);
   int loBar = iLowest(_Symbol, _Period, MODE_LOW, Inp_TrendLookback, 2);
   if(hiBar < 0 || loBar < 0)
      return 0;

   double c1 = iClose(_Symbol, _Period, 1), o1 = iOpen(_Symbol, _Period, 1);
   double h1 = iHigh(_Symbol, _Period, 1), l1 = iLow(_Symbol, _Period, 1);
   double range = h1-l1;
   if(range <= 0.0)
      return 0;

   double atrNow = GetATR_Val(1);
   double atrAvg = GetATRAvg(Inp_ATRAvgPeriod);
   if(atrNow <= 0.0 || atrAvg <= 0.0)
      return 0;

   // Volatility expansion: current ATR vs its own recent average
   bool expansion = (atrNow > atrAvg * Inp_ExpansionFactor);
   bool solidBody = (MathAbs(c1-o1)/range >= Inp_BodyRatio);

   if(c1 > iHigh(_Symbol, _Period, hiBar) && solidBody && expansion) return 1;
   if(c1 < iLow(_Symbol, _Period, loBar)  && solidBody && expansion) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| ENTRY FILTERS                                                     |
//+------------------------------------------------------------------+
bool IsWithinSession()
  {
   if(Inp_SessionStartHour == Inp_SessionEndHour)
      return true;                                   // disabled
   if(Inp_SessionStartHour == 0 && Inp_SessionEndHour >= 24)
      return true;                                   // disabled

   MqlDateTime t;
   TimeCurrent(t);
   int h = t.hour;

   if(Inp_SessionStartHour < Inp_SessionEndHour)
      return (h >= Inp_SessionStartHour && h < Inp_SessionEndHour);
   return (h >= Inp_SessionStartHour || h < Inp_SessionEndHour);   // wraps midnight
  }

//+------------------------------------------------------------------+
bool HTFTrendAllows(bool isBuy)
  {
   if(!Inp_UseHTFFilter)
      return true;
   if(hHTFEMA == INVALID_HANDLE)
      return false;

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hHTFEMA, 0, 1, 1, buf) <= 0)
      return false;

   double ema   = buf[0];
   double close1 = iClose(_Symbol, _Period, 1);
   return isBuy ? (close1 > ema) : (close1 < ema);
  }

//+------------------------------------------------------------------+
//| EXECUTION                                                         |
//+------------------------------------------------------------------+
void ExecuteRetestEntry(bool isBuy)
  {
   double open1 = iOpen(_Symbol, _Period, 1), close1 = iClose(_Symbol, _Period, 1);
   double limitPrice = NormalizeDouble((open1 + close1) / 2.0, _Digits);

   // SL/TP distance in points (ATR-based or fixed)
   int slPoints, tpPoints;
   if(Inp_UseATR_SLTP)
     {
      double atr = GetATR_Val(1);
      if(atr <= 0.0)
        {
         Print("Entry skipped: no ATR value for SL/TP calculation");
         return;
        }
      slPoints = (int)MathRound(Inp_SL_ATRMult * atr / _Point);
      tpPoints = (int)MathRound(Inp_TP_ATRMult * atr / _Point);
     }
   else
     {
      slPoints = Inp_SL_Points;
      tpPoints = Inp_TP_Points;
     }
   if(slPoints <= 0 || tpPoints <= 0)
     {
      Print("Entry skipped: invalid SL/TP distance");
      return;
     }

   double lot = CalculateLotSize(slPoints);
   if(lot <= 0.0)
      return;   // CalculateLotSize already logged the reason

   double sl = isBuy ? limitPrice - slPoints * _Point : limitPrice + slPoints * _Point;
   double tp = isBuy ? limitPrice + tpPoints * _Point : limitPrice - tpPoints * _Point;

   if(!ValidateLimitOrder(isBuy, limitPrice, sl, tp))
      return;

   // BuyLimit/SellLimit map the price into request.price correctly
   // (raw OrderOpen would place it into request.stoplimit)
   bool ok = isBuy
             ? m_trade.BuyLimit(lot, limitPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "MQL5-Retest")
             : m_trade.SellLimit(lot, limitPrice, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "MQL5-Retest");
   if(!ok)
      Print("Order placement failed: ", m_trade.ResultRetcodeDescription());
   else
      Print("Limit Order Placed at: ", DoubleToString(limitPrice, _Digits),
            " lot=", DoubleToString(lot, VolumeDigits(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP))),
            " sl=", DoubleToString(sl, _Digits), " tp=", DoubleToString(tp, _Digits));
  }

//+------------------------------------------------------------------+
bool ValidateLimitOrder(bool isBuy, double price, double sl, double tp)
  {
   if(price <= 0.0 || sl <= 0.0 || tp <= 0.0)
     {
      Print("Invalid order: non-positive price/SL/TP");
      return false;
     }

   double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(isBuy)
     {
      if(price >= bid - stopsLevel)
        {
         Print("Invalid BUY LIMIT: price ", DoubleToString(price, _Digits),
               " not at least stops-level below bid ", DoubleToString(bid, _Digits));
         return false;
        }
     }
   else
     {
      if(price <= ask + stopsLevel)
        {
         Print("Invalid SELL LIMIT: price ", DoubleToString(price, _Digits),
               " not at least stops-level above ask ", DoubleToString(ask, _Digits));
         return false;
        }
     }

   if(MathAbs(price - sl) < stopsLevel)
     {
      Print("Invalid order: SL closer than stops level (", (int)stopsLevel, " points)");
      return false;
     }
   if(MathAbs(price - tp) < stopsLevel)
     {
      Print("Invalid order: TP closer than stops level (", (int)stopsLevel, " points)");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| HELPERS                                                           |
//+------------------------------------------------------------------+
double GetATR_Val(int shift)
  {
   if(hATR == INVALID_HANDLE)
      return 0;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   if(CopyBuffer(hATR, 0, shift, 1, buffer) > 0)
      return buffer[0];
   return 0;
  }

//+------------------------------------------------------------------+
//| Average ATR over `period` bars, starting at bar 2 (excludes the   |
//| signal bar itself)                                                |
//+------------------------------------------------------------------+
double GetATRAvg(int period)
  {
   if(hATR == INVALID_HANDLE || period < 2)
      return 0;

   double buffer[];
   ArraySetAsSeries(buffer, true);
   int copied = CopyBuffer(hATR, 0, 2, period, buffer);
   if(copied <= 0)
      return 0;

   double sum = 0;
   for(int i = 0; i < copied; i++)
      sum += buffer[i];
   return sum / copied;
  }

//+------------------------------------------------------------------+
//| Decimal places used by the symbol's volume step                   |
//+------------------------------------------------------------------+
int VolumeDigits(double step)
  {
   int digits = 0;
   double v = step;
   while(digits < 8 && MathAbs(v - MathRound(v)) > 1e-8)
     {
      v *= 10.0;
      digits++;
     }
   return digits;
  }

//+------------------------------------------------------------------+
//| Risk-based lot size. Returns 0 (and logs why) when the trade      |
//| cannot be sized within the chosen risk.                           |
//+------------------------------------------------------------------+
double CalculateLotSize(int slPoints)
  {
   double risk     = AccountInfoDouble(ACCOUNT_EQUITY) * (Inp_RiskPercent / 100.0);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double step     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(slPoints <= 0 || tickSize <= 0.0 || tickVal <= 0.0 || step <= 0.0)
     {
      Print("Lot calc failed: invalid symbol parameters");
      return 0.0;
     }

   double slTicks = (slPoints * _Point) / tickSize;
   if(slTicks <= 0.0)
     {
      Print("Lot calc failed: SL distance is zero ticks");
      return 0.0;
     }

   double lot = risk / (slTicks * tickVal);
   lot = MathFloor(lot / step) * step;
   lot = NormalizeDouble(lot, VolumeDigits(step));

   if(lot < minLot)
     {
      if(Inp_AllowMinLotFloor)
        {
         Print("Calculated lot ", DoubleToString(lot, VolumeDigits(step)),
               " below minimum ", DoubleToString(minLot, VolumeDigits(step)),
               " - floored to min lot (Inp_AllowMinLotFloor=true, actual risk >> Inp_RiskPercent)");
         return NormalizeDouble(minLot, VolumeDigits(step));
        }
      Print("Trade skipped: calculated lot ", DoubleToString(lot, VolumeDigits(step)),
            " is below minimum ", DoubleToString(minLot, VolumeDigits(step)),
            " (equity too small for chosen risk)");
      return 0.0;
     }
   if(lot > maxLot)
      lot = maxLot;
   return lot;
  }

//+------------------------------------------------------------------+
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
//| True when a pending order for this symbol/magic already exists    |
//+------------------------------------------------------------------+
bool HasOpenOrder()
  {
   for(int i=0; i<OrdersTotal(); i++)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol && OrderGetInteger(ORDER_MAGIC) == Inp_MagicNum)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| TRADE MANAGEMENT                                                  |
//+------------------------------------------------------------------+
void ManageTrades()
  {
   ManagePositions();
   ManagePendingOrders();
  }

//+------------------------------------------------------------------+
//| Breakeven + ATR trailing, one modification per tick at most       |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   if(!Inp_UseTrailing && !Inp_UseBE)
      return;

   double atr = GetATR_Val(1);
   if(atr <= 0.0)
      return;

   double stopsLevel = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double trailStep = Inp_TrailStepATR * atr;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != Inp_MagicNum || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      double curSL  = PositionGetDouble(POSITION_SL);
      double tp     = PositionGetDouble(POSITION_TP);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      bool   slValid = (curSL > 0.0);
      double newSL  = curSL;

      if(isBuy)
        {
         if(Inp_UseBE && (bid - entry >= Inp_BE_TriggerATR * atr))
           {
            double beLevel = NormalizeDouble(entry + MathMax(Inp_BE_BufferPoints * _Point, stopsLevel), _Digits);
            if(!slValid || beLevel > newSL)
               newSL = beLevel;
           }
         if(Inp_UseTrailing)
           {
            double candSL = NormalizeDouble(bid - (atr * Inp_TrailMult), _Digits);
            if(candSL > newSL + trailStep)
               newSL = candSL;
           }
         bool changed = slValid ? (newSL > curSL) : (newSL > 0.0);
         if(changed && bid - newSL >= stopsLevel)
            ModifyPosition(ticket, newSL, tp);
        }
      else
        {
         if(Inp_UseBE && (entry - ask >= Inp_BE_TriggerATR * atr))
           {
            double beLevel = NormalizeDouble(entry - MathMax(Inp_BE_BufferPoints * _Point, stopsLevel), _Digits);
            if(!slValid || beLevel < newSL)
               newSL = beLevel;
           }
         if(Inp_UseTrailing)
           {
            double candSL = NormalizeDouble(ask + (atr * Inp_TrailMult), _Digits);
            if(!slValid || candSL < newSL - trailStep)
               newSL = candSL;
           }
         bool changed = slValid ? (newSL < curSL) : (newSL > 0.0);
         if(changed && newSL - ask >= stopsLevel)
            ModifyPosition(ticket, newSL, tp);
        }
     }
  }

//+------------------------------------------------------------------+
void ModifyPosition(ulong ticket, double sl, double tp)
  {
   if(!m_trade.PositionModify(ticket, sl, tp))
      Print("PositionModify failed for #", ticket, ": ", m_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Cleanup of stale / weekend pending orders                         |
//+------------------------------------------------------------------+
void ManagePendingOrders()
  {
   bool fridayCleanup = false;
   if(Inp_FridayCleanupHour >= 0 && Inp_FridayCleanupHour <= 23)
     {
      MqlDateTime t;
      TimeCurrent(t);
      fridayCleanup = (t.day_of_week == 5 && t.hour >= Inp_FridayCleanupHour);
     }

   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket==0 || !OrderSelect(ticket))
         continue;

      if(OrderGetInteger(ORDER_MAGIC) != Inp_MagicNum || OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;

      bool del = fridayCleanup;
      if(!del)
        {
         datetime setup=(datetime)OrderGetInteger(ORDER_TIME_SETUP);
         int barsElapsed=iBarShift(_Symbol, _Period, setup);
         del = (barsElapsed >= Inp_BarsToWait);
        }

      if(del)
        {
         if(!m_trade.OrderDelete(ticket))
            Print("OrderDelete failed for #", ticket, ": ", m_trade.ResultRetcodeDescription());
         else
            Print("Pending order #", ticket, " deleted (",
                  (fridayCleanup ? "Friday cleanup" : "expired"), ")");
        }
     }
  }

//+------------------------------------------------------------------+
double OnTester()
  {
   long trades=(long)TesterStatistics(STAT_TRADES);
   if(trades<Inp_MinTradesForScore) return(0.0);

   double maxDD=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(maxDD>Inp_MaxDDPercent) return(0.0);

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
