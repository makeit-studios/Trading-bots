//+------------------------------------------------------------------+
//|                                          LiquidityZoneEA.mq5     |
//|                     3-Core-Parameter Supply/Demand EA + Risk     |
//+------------------------------------------------------------------+
#property copyright "Free - Build with AI"
#property version   "3.00"
#property description "Supply/demand liquidity zones. Only 3 core tuning params. Everything else static."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- THE ONLY 3 PARAMETERS YOU SHOULD EVER TUNE ---
input double   MinImpulseATR   = 1.0;    // 0.8=more zones, 1.5=fewer/stronger
input double   RatioMultiplier = 2.0;    // 1.5=looser, 3.0=tighter zones
input double   RiskPercent     = 1.0;    // % of account risked per trade

//--- Everything below is STATIC. No optimization needed. ---
#define REWARD_MULTIPLIER     3.0        // Fixed 1:3 RR
#define ATR_PERIOD            14
#define LOOKBACK_BARS         500
#define SWING_BARS            3
#define SL_OFFSET_POINTS      20
#define PENDING_EXPIRY_HOURS  24
#define MAX_POSITIONS         1
#define MAX_DAILY_LOSS_PCT    5.0
#define MAX_DRAWDOWN_PCT      15.0
#define MAX_CONSECUTIVE_LOSS  4
#define COOLDOWN_HOURS        4
#define SLIPPAGE_BUFFER_PTS   4.0
#define NEWS_BLOCK_MINUTES    30
#define FRIDAY_CLOSE_HOUR     21

#define DEMAND_COLOR          clrDodgerBlue
#define SUPPLY_COLOR          clrOrangeRed
#define SHOW_ZONES            true

CTrade          trade;
CPositionInfo   position;
CAccountInfo    account;
CSymbolInfo     symbolInfo;
int             atrHandle;
double          atrBuffer[];
datetime        lastBarTime = 0;
const ulong     magicNumber = 20260701;

struct RiskState {
   double   peakEquity;
   double   dayStartEquity;
   int      consecutiveLosses;
   datetime coolDownUntil;
   bool     halted;
   datetime haltTime;
};
RiskState risk;

string stateFileName;

struct SZone {
   datetime   time;
   double     priceHigh;
   double     priceLow;
   bool       isDemand;
   double     strength;
   bool       active;
};
SZone zones[];
int zoneCount = 0;

//+------------------------------------------------------------------+
int OnInit() {
   trade.SetExpertMagicNumber(magicNumber);
   trade.SetDeviationInPoints(SLIPPAGE_BUFFER_PTS);

   symbolInfo.Name(_Symbol);
   symbolInfo.Refresh();

   atrHandle = iATR(_Symbol, _Period, ATR_PERIOD);
   if(atrHandle == INVALID_HANDLE)
      return INIT_FAILED;

   ArraySetAsSeries(atrBuffer, true);
   stateFileName = "LZoneEA_" + _Symbol + "_" + (string)_Period + ".json";
   LoadState();

   risk.dayStartEquity = account.Equity();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   SaveState();
   if(atrHandle != INVALID_HANDLE)
      IndicatorRelease(atrHandle);
   DeleteZoneObjects();
}

//+------------------------------------------------------------------+
void OnTick() {
   datetime bt = iTime(_Symbol, _Period, 0);
   if(bt == lastBarTime) return;
   lastBarTime = bt;

   NewDayCheck();

   if(!CanTrade()) return;

   ScanForZones();
   ManagePositions();

   if(PositionsTotal() < MAX_POSITIONS && !InCoolDown())
      CheckEntries();
}

//+------------------------------------------------------------------+
bool CanTrade() {
   //--- Halt
   if(risk.halted) {
      if(risk.haltTime > 0 && TimeCurrent() - risk.haltTime > 86400)
         risk.halted = false;
      else return false;
   }

   double eq = account.Equity();

   //--- Drawdown gate
   if(eq > risk.peakEquity) risk.peakEquity = eq;
   double dd = risk.peakEquity > 0 ? (1.0 - eq / risk.peakEquity) * 100.0 : 0;
   if(dd >= MAX_DRAWDOWN_PCT) {
      if(!risk.halted) {
         risk.halted = true;
         risk.haltTime = TimeCurrent();
         Print("HALT: dd ", DoubleToString(dd,1), "% >= ", MAX_DRAWDOWN_PCT, "%");
         CloseAll("dd_halt");
      }
      return false;
   }

   //--- Daily loss gate
   double dayLoss = risk.dayStartEquity > 0 ? (1.0 - eq / risk.dayStartEquity) * 100.0 : 0;
   if(dayLoss >= MAX_DAILY_LOSS_PCT) return false;

   //--- News gate
   MqlDateTime dt;
   TimeCurrent(dt);
   int h = dt.hour, m = dt.min;
   if(h == 8 && m < NEWS_BLOCK_MINUTES) return false;   // London open
   if(h == 13 && m < NEWS_BLOCK_MINUTES) return false;   // US open
   if(dt.day_of_week == 5 && h == 13) return false;      // NFP

   //--- Friday close
   if(dt.day_of_week == 5 && h >= FRIDAY_CLOSE_HOUR) return false;

   return true;
}

//+------------------------------------------------------------------+
void NewDayCheck() {
   static int lastDay = 0;
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.day == lastDay) return;
   lastDay = dt.day;
   risk.dayStartEquity = account.Equity();
   if(dt.day_of_week == 1) {
      risk.consecutiveLosses = 0;
      risk.coolDownUntil = 0;
   }
}

//+------------------------------------------------------------------+
bool InCoolDown() {
   if(risk.coolDownUntil > 0) {
      if(TimeCurrent() < risk.coolDownUntil) return true;
      risk.coolDownUntil = 0;
      risk.consecutiveLosses = 0;
   }
   return false;
}

//+------------------------------------------------------------------+
void ScanForZones() {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 0, LOOKBACK_BARS, rates);
   if(copied < SWING_BARS * 2 + 2) return;

   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) < 1) return;
   double atr = atrBuffer[0];

   zoneCount = 0;
   DeleteZoneObjects();

   for(int i = SWING_BARS + 1; i < copied - 1; i++) {
      int base = i, imp = i - 1;
      double baseR = rates[base].high - rates[base].low;
      double impR  = rates[imp].high - rates[imp].low;
      if(baseR == 0) continue;
      if(impR < atr * MinImpulseATR) continue;
      if(impR / baseR < RatioMultiplier) continue;

      bool up = rates[imp].close > rates[imp].open;
      bool dn = rates[imp].close < rates[imp].open;
      if(!up && !dn) continue;

      AddZone(rates[base].time, rates[base].high, rates[base].low,
              up, impR / atr);
   }
}

//+------------------------------------------------------------------+
void AddZone(datetime t, double h, double l, bool isDemand, double str) {
   double atr = currentATR();
   if(atr > 0)
      for(int i = 0; i < zoneCount; i++)
         if(MathAbs(zones[i].priceHigh - h) < atr * 0.3 && zones[i].isDemand == isDemand)
            return;

   int idx = zoneCount++;
   if(ArraySize(zones) < zoneCount) ArrayResize(zones, zoneCount + 50);
   zones[idx].time = t;
   zones[idx].priceHigh = h;
   zones[idx].priceLow = l;
   zones[idx].isDemand = isDemand;
   zones[idx].strength = str;
   zones[idx].active = true;

   if(SHOW_ZONES) {
      color clr = isDemand ? DEMAND_COLOR : SUPPLY_COLOR;
      string p = "LZ_" + (string)idx;
      ObjectCreate(0, p+"_r", OBJ_RECTANGLE, 0, t, h, t+PENDING_EXPIRY_HOURS*3600, l);
      ObjectSetInteger(0, p+"_r", OBJPROP_COLOR, clr);
      ObjectSetInteger(0, p+"_r", OBJPROP_FILL, true);
      ObjectSetInteger(0, p+"_r", OBJPROP_BACK, true);
      ObjectSetInteger(0, p+"_r", OBJPROP_RAY_RIGHT, true);

      string lbl = (isDemand ? "DEMAND" : "SUPPLY") + " S:" + DoubleToString(str,1) + "x";
      ObjectCreate(0, p+"_l", OBJ_TEXT, 0, t, h);
      ObjectSetString(0, p+"_l", OBJPROP_TEXT, lbl);
      ObjectSetInteger(0, p+"_l", OBJPROP_COLOR, clr);
      ObjectSetInteger(0, p+"_l", OBJPROP_FONTSIZE, 8);
   }
}

//+------------------------------------------------------------------+
void CheckEntries() {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double offset = SL_OFFSET_POINTS * pt;
   datetime expiry = TimeCurrent() + PENDING_EXPIRY_HOURS * 3600;

   ResetLastError();

   for(int i = 0; i < zoneCount; i++) {
      if(!zones[i].active) continue;
      double h = zones[i].priceHigh, l = zones[i].priceLow;
      double mid = (h + l) / 2.0;

      double spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * pt * 2;
      if(MathAbs(bid - mid) < spreadPts && MathAbs(ask - mid) < spreadPts) continue;

      if(zones[i].isDemand && bid <= h) {
         double sl = l - offset;
         double riskD = mid - sl;
         if(riskD <= 0) continue;
         double tp = mid + riskD * REWARD_MULTIPLIER;
         double lot = CalcLot(riskD);
         if(lot <= 0) continue;

          if(trade.BuyLimit(lot, mid, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry)) {
            Print("BUY L:", lot, " @", mid, " SL:", sl, " TP:", tp);
            zones[i].active = false;
         } else Print("BUY FAIL err:", GetLastError(), " rc:", trade.ResultRetcode());
      }
      else if(!zones[i].isDemand && ask >= l) {
         double sl = h + offset;
         double riskD = sl - mid;
         if(riskD <= 0) continue;
         double tp = mid - riskD * REWARD_MULTIPLIER;
         double lot = CalcLot(riskD);
         if(lot <= 0) continue;

          if(trade.SellLimit(lot, mid, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, expiry)) {
            Print("SELL L:", lot, " @", mid, " SL:", sl, " TP:", tp);
            zones[i].active = false;
         } else Print("SELL FAIL err:", GetLastError(), " rc:", trade.ResultRetcode());
      }
   }
}

//+------------------------------------------------------------------+
double CalcLot(double riskDist) {
   double cap = MathMin(account.Balance(), account.Equity());
   double riskAmt = cap * RiskPercent / 100.0;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(tv <= 0 || ts <= 0 || riskDist <= 0) return 0;

   double effRisk = riskDist + SLIPPAGE_BUFFER_PTS * pt;
   double lot = riskAmt / ((effRisk / ts) * tv);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot / step) * step;
   return MathMax(vMin, MathMin(vMax, lot));
}

//+------------------------------------------------------------------+
void ManagePositions() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!position.SelectByIndex(i)) continue;
      if(position.Magic() != magicNumber) continue;
      if(position.Symbol() != _Symbol) continue;
   }
}

//+------------------------------------------------------------------+
void CloseAll(string reason) {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      if(!position.SelectByIndex(i)) continue;
      if(position.Magic() != magicNumber || position.Symbol() != _Symbol) continue;
      if(trade.PositionClose(position.Ticket()))
         Print("Closed ", position.Ticket(), " ", reason);
      else
         Print("Close fail ", position.Ticket(), " err:", GetLastError());
   }
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult &res) {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
      HistorySelect(0, TimeCurrent());
      int total = HistoryDealsTotal();
      if(total <= 0) return;
      ulong ticket = HistoryDealGetTicket(total - 1);
      if(ticket <= 0) return;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magicNumber) return;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      if(profit < 0) {
         risk.consecutiveLosses++;
         if(risk.consecutiveLosses >= MAX_CONSECUTIVE_LOSS) {
            risk.coolDownUntil = TimeCurrent() + COOLDOWN_HOURS * 3600;
            Print("Cooldown: ", risk.consecutiveLosses, " losses. Resume ", TimeToString(risk.coolDownUntil));
         }
      } else if(profit > 0) {
         risk.consecutiveLosses = 0;
         risk.coolDownUntil = 0;
      }
   }
}

//+------------------------------------------------------------------+
double currentATR() {
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) < 1) return 0;
   return atrBuffer[0];
}

//+------------------------------------------------------------------+
void SaveState() {
   string j = "{";
   j += "\"pe\":" + DoubleToString(risk.peakEquity,2) + ",";
   j += "\"de\":" + DoubleToString(risk.dayStartEquity,2) + ",";
   j += "\"cl\":" + (string)risk.consecutiveLosses + ",";
   j += "\"cd\":" + (string)risk.coolDownUntil + ",";
   j += "\"ha\":" + (risk.halted?"1":"0") + ",";
   j += "\"ht\":" + (string)risk.haltTime;
   j += "}";

   int h = FileOpen(stateFileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(h != INVALID_HANDLE) { FileWrite(h, j); FileClose(h); }
}

//+------------------------------------------------------------------+
void LoadState() {
   risk.peakEquity = account.Equity();
   risk.dayStartEquity = account.Equity();

   int h = FileOpen(stateFileName, FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE) return;
   string j = FileReadString(h);
   FileClose(h);

   risk.peakEquity      = JGetD(j, "pe", account.Equity());
   risk.dayStartEquity  = JGetD(j, "de", account.Equity());
   risk.consecutiveLosses = (int)JGetD(j, "cl", 0);
   risk.coolDownUntil   = (datetime)JGetD(j, "cd", 0);
   risk.halted          = JGetD(j, "ha", 0) > 0.5;
   risk.haltTime        = (datetime)JGetD(j, "ht", 0);

   Print("State: peakEq=", risk.peakEquity);
}

//+------------------------------------------------------------------+
double JGetD(string json, string key, double def) {
   string s = "\"" + key + "\":";
   int p = StringFind(json, s);
   if(p < 0) return def;
   p += StringLen(s);
   int e = StringFind(json, ",", p);
   int e2 = StringFind(json, "}", p);
   if(e < 0 || (e2 >= 0 && e2 < e)) e = e2;
   if(e < 0) return def;
   string v = StringSubstr(json, p, e - p);
   StringReplace(v, " ", "");
   return (v == "" || v == "null") ? def : StringToDouble(v);
}

//+------------------------------------------------------------------+
void DeleteZoneObjects() {
   for(int i = ObjectsTotal(0, -1) - 1; i >= 0; i--) {
      string n = ObjectName(0, i);
      if(StringFind(n, "LZ_") == 0) ObjectDelete(0, n);
   }
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
