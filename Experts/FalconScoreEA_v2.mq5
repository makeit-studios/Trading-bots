//+------------------------------------------------------------------+
//| FalconScoreEA_v2.mq5                                             |
//| Score-based Falcon strategy v2 - 5 core params, full risk mgmt   |
//| v2.00                                                           |
//+------------------------------------------------------------------+
#property copyright "Falcon Strategy v2"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| HARDCODED CONSTANTS (NOT tunable - prevents overfitting)         |
//+------------------------------------------------------------------+
// --- Risk Management ---
#define DAILY_LOSS_PERCENT      5.0
#define DRAWDOWN_HALT_PERCENT   15.0
#define MAX_CONSECUTIVE_LOSSES  4
#define COOLDOWN_HOURS          4
#define FRIDAY_CLOSE_HOUR      21
#define MAX_DAILY_TRADES        3
#define LOSS_SIZE_DECAY         0.20
#define MIN_SIZE_MULTIPLIER     0.50

// --- Trade Management ---
#define REWARD_MULTIPLIER       3.0
#define SL_BUFFER_POINTS        25.0
#define MIN_SL_ATR_MULT         1.0
#define MAX_SL_ATR_MULT         2.5
#define TRAIL_ATR_MULT          1.1
#define BREAKEVEN_ATR_MULT      1.0

// --- Pattern Detection ---
#define SWING_LOOKBACK_BARS     10
#define ARC_LOOKBACK            10
#define ARC_TOLERANCE_PTS       15.0
#define RETEST_LOOKBACK_FAR     250
#define MIN_RETESTS_FOR_LEVEL   3
#define MOMENTUM_BODY_MIN_RATIO 0.60
#define MIN_WICK_RATIO          0.35
#define FLAG_IMPULSE_BARS       8
#define FLAG_CORRECTION_BARS    26
#define WEDGE_WIDE_BARS         12
#define WEDGE_TIGHT_BARS        1

// --- Execution ---
#define SLIPPAGE_BUFFER_POINTS  3
#define MAX_SPREAD_MULTIPLIER   3.0
#define MIN_FREE_MARGIN_PCT     25.0
#define PEAK_UPDATE_INTERVAL_SEC 60

// --- State File ---
#define STATE_FOLDER            "FalconScoreEA_v2"

//+------------------------------------------------------------------+
//| Enums                                                            |
//+------------------------------------------------------------------+
enum ENUM_TREND_STATE
  {
   TREND_UP,
   TREND_DOWN,
   TREND_SIDEWAYS
  };

//+------------------------------------------------------------------+
//| CORE INPUTS (only 5 - everything else is #define)                |
//+------------------------------------------------------------------+
input string Inp_ExpertTitle           ="Falcon_v2";
input int    Inp_MagicNumber           =12004;
input double Inp_RiskPercent           =1.0;
input int    Inp_MinScoreToTrade       =3;
input int    Inp_ATR_Period            =14;
input int    Inp_TrendLookback         =120;

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade        ExtTrade;
int           atrHandle=INVALID_HANDLE;
double        atrBuffer[];
datetime      lastBarTime=0;
datetime      lastPeakUpdate=0;
double        cachedATR=0.0;
datetime      cachedATRBar=0;

//--- Risk State ---
struct RiskState
  {
   double        peakEquity;
   double        dayStartEquity;
   int           consecutiveLosses;
   datetime      cooldownUntil;
   int           lastDate;
   int           dailyTrades;
   int           lossStreak;

   void Init()
     {
      peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      dayStartEquity=peakEquity;
      consecutiveLosses=0;
      cooldownUntil=0;
      lastDate=DateToDay(TimeCurrent());
      dailyTrades=0;
      lossStreak=0;
     }

   int DateToDay(datetime t) const
     {
      MqlDateTime dt;
      TimeToStruct(t,dt);
      return(dt.year*10000 + dt.mon*100 + dt.day);
     }
  };

RiskState g_state;

//--- History scanning ---
datetime g_lastHistoryScan=0;

//+------------------------------------------------------------------+
//| Log helper                                                       |
//+------------------------------------------------------------------+
void Log(const string msg)
  {
   Print("[",Inp_ExpertTitle,"] ",msg);
  }

//+------------------------------------------------------------------+
//| Bar management                                                   |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   datetime t=iTime(_Symbol,_Period,0);
   if(t!=lastBarTime)
     {
      lastBarTime=t;
      return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| ATR with caching                                                 |
//+------------------------------------------------------------------+
double GetATR(const int index)
  {
   if(atrHandle==INVALID_HANDLE)
      return(0.0);
   if(index==1 && cachedATRBar==lastBarTime)
      return(cachedATR);
   if(CopyBuffer(atrHandle,0,index,1,atrBuffer)<1)
      return(0.0);
   if(index==1)
     {
      cachedATR=atrBuffer[0];
      cachedATRBar=lastBarTime;
     }
   return(atrBuffer[0]);
  }

//+------------------------------------------------------------------+
//| Position counting                                                |
//+------------------------------------------------------------------+
int CountOurPositions()
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==Inp_MagicNumber)
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| RISK MANAGEMENT LAYER                                           |
//+------------------------------------------------------------------+

//--- State file path ---
string StateFilePath()
  {
   string filename=STATE_FOLDER+"\\"+_Symbol+"_"+EnumToString((ENUM_TIMEFRAMES)_Period)+".state";
   return(filename);
  }

bool SaveState()
  {
   int handle=FileOpen(StateFilePath(),FILE_TXT|FILE_COMMON|FILE_WRITE);
   if(handle==INVALID_HANDLE)
      return(false);
   FileWrite(handle,
             DoubleToString(g_state.peakEquity,2),
             DoubleToString(g_state.dayStartEquity,2),
             (string)g_state.consecutiveLosses,
             (string)g_state.cooldownUntil,
             (string)g_state.lastDate,
             (string)g_state.dailyTrades,
             (string)g_state.lossStreak);
   FileClose(handle);
   return(true);
  }

bool LoadState()
  {
   int handle=FileOpen(StateFilePath(),FILE_TXT|FILE_COMMON|FILE_READ);
   if(handle==INVALID_HANDLE)
      return(false);
   g_state.peakEquity=StringToDouble(FileReadString(handle));
   g_state.dayStartEquity=StringToDouble(FileReadString(handle));
   g_state.consecutiveLosses=(int)StringToInteger(FileReadString(handle));
   g_state.cooldownUntil=(datetime)StringToInteger(FileReadString(handle));
   g_state.lastDate=(int)StringToInteger(FileReadString(handle));
   g_state.dailyTrades=(int)StringToInteger(FileReadString(handle));
   g_state.lossStreak=(int)StringToInteger(FileReadString(handle));
   FileClose(handle);
   return(true);
  }

//--- Day change detection ---
void CheckDayChange()
  {
   int today=g_state.DateToDay(TimeCurrent());
   if(today!=g_state.lastDate)
     {
      g_state.dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      g_state.dailyTrades=0;
      g_state.lastDate=today;
      SaveState();
     }
  }

//--- Peak equity update (periodic) ---
void UpdatePeakEquity()
  {
   datetime now=TimeCurrent();
   if(now-lastPeakUpdate<PEAK_UPDATE_INTERVAL_SEC)
      return;
   lastPeakUpdate=now;
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>g_state.peakEquity)
     {
      g_state.peakEquity=eq;
      SaveState();
     }
  }

//--- Circuit breaker checks ---
bool IsInCooldown()
  {
   if(g_state.cooldownUntil==0)
      return(false);
   if(TimeCurrent()>=g_state.cooldownUntil)
     {
      g_state.cooldownUntil=0;
      g_state.consecutiveLosses=0;
      SaveState();
      return(false);
     }
   return(true);
  }

bool IsDailyLossExceeded()
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct=(g_state.dayStartEquity>0) ? ((g_state.dayStartEquity-equity)/g_state.dayStartEquity)*100.0 : 0.0;
   return(lossPct>=DAILY_LOSS_PERCENT);
  }

bool IsDrawdownHalted()
  {
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct=(g_state.peakEquity>0) ? ((g_state.peakEquity-equity)/g_state.peakEquity)*100.0 : 0.0;
   return(ddPct>=DRAWDOWN_HALT_PERCENT);
  }

bool IsMaxDailyTradesReached()
  {
   return(g_state.dailyTrades>=MAX_DAILY_TRADES);
  }

//--- Friday close check ---
bool IsFridayCloseTime()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   if(dt.day_of_week!=5)
      return(false);
   return(dt.hour>=FRIDAY_CLOSE_HOUR);
  }

//--- News block ---
bool IsNewsBlock()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
   int hour=dt.hour;
   int min=dt.min;
   int totalMin=hour*60+min;
   // London open: 08:00-08:05 UTC
   if(totalMin>=480 && totalMin<=485) return(true);
   // US open: 13:30-13:35 UTC
   if(totalMin>=810 && totalMin<=815) return(true);
   return(false);
  }

//--- Combined risk gate ---
bool RiskGateAllowsTrading()
  {
   if(IsInCooldown())
     {
      Log("RiskGate: cooldown active until "+(string)g_state.cooldownUntil);
      return(false);
     }
   if(IsDailyLossExceeded())
     {
      Log("RiskGate: daily loss cap hit");
      return(false);
     }
   if(IsDrawdownHalted())
     {
      Log("RiskGate: drawdown limit breached");
      return(false);
     }
   if(IsMaxDailyTradesReached())
     {
      Log("RiskGate: max daily trades reached");
      return(false);
     }
   if(IsFridayCloseTime())
     {
      Log("RiskGate: Friday close window");
      return(false);
     }
   if(IsNewsBlock())
     {
      Log("RiskGate: news block active");
      return(false);
     }
   return(true);
  }



//--- Position size decay based on loss streak ---
double GetSizeMultiplier()
  {
   double m=1.0-(g_state.lossStreak*LOSS_SIZE_DECAY);
   if(m<MIN_SIZE_MULTIPLIER) m=MIN_SIZE_MULTIPLIER;
   return(m);
  }

//--- Friday close: close all positions ---
void CloseAllOurPositions()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==Inp_MagicNumber)
        {
         ExtTrade.PositionClose(ticket);
        }
     }
  }

//+------------------------------------------------------------------+
//| SIGNAL GENERATION LAYER                                         |
//+------------------------------------------------------------------+

ENUM_TREND_STATE GetMarketStructureTrend()
  {
   double high1=0, high2=0, low1=0, low2=0;
   int foundH=0, foundL=0;

   int maxBars=MathMin(Inp_TrendLookback,Bars(_Symbol,_Period)-2);
   if(maxBars<6)
      return(TREND_SIDEWAYS);

   for(int i=2;i<maxBars && (foundH<2 || foundL<2);i++)
     {
      if(iHigh(_Symbol,_Period,i)>iHigh(_Symbol,_Period,i+1) && iHigh(_Symbol,_Period,i)>iHigh(_Symbol,_Period,i-1))
        {
         if(foundH==0) high1=iHigh(_Symbol,_Period,i);
         else if(foundH==1) high2=iHigh(_Symbol,_Period,i);
         foundH++;
        }
      if(iLow(_Symbol,_Period,i)<iLow(_Symbol,_Period,i+1) && iLow(_Symbol,_Period,i)<iLow(_Symbol,_Period,i-1))
        {
         if(foundL==0) low1=iLow(_Symbol,_Period,i);
         else if(foundL==1) low2=iLow(_Symbol,_Period,i);
         foundL++;
        }
     }

   if(foundH<2 || foundL<2)
      return(TREND_SIDEWAYS);
   if(high1>high2 && low1>low2) return(TREND_UP);
   if(high1<high2 && low1<low2) return(TREND_DOWN);
   return(TREND_SIDEWAYS);
  }

bool IsFlagPattern()
  {
   double impulse=MathAbs(iClose(_Symbol,_Period,FLAG_IMPULSE_BARS)-iClose(_Symbol,_Period,FLAG_CORRECTION_BARS));
   int hiIdx=iHighest(_Symbol,_Period,MODE_HIGH,FLAG_IMPULSE_BARS,1);
   int loIdx=iLowest(_Symbol,_Period,MODE_LOW,FLAG_IMPULSE_BARS,1);
   if(hiIdx<0 || loIdx<0 || impulse<=0.0)
      return(false);
   double correction=iHigh(_Symbol,_Period,hiIdx)-iLow(_Symbol,_Period,loIdx);
   return(correction<impulse*0.40);
  }

bool IsWedgeReversal()
  {
   double wide=iHigh(_Symbol,_Period,WEDGE_WIDE_BARS)-iLow(_Symbol,_Period,WEDGE_WIDE_BARS);
   double tight=iHigh(_Symbol,_Period,WEDGE_TIGHT_BARS)-iLow(_Symbol,_Period,WEDGE_TIGHT_BARS);
   if(wide<=0.0)
      return(false);
   return(tight<wide*0.55);
  }

bool IsArcTrigger(const bool buy)
  {
   if(ARC_LOOKBACK<3)
      return(false);
   double current=buy ? iLow(_Symbol,_Period,1) : iHigh(_Symbol,_Period,1);
   for(int i=3;i<=ARC_LOOKBACK;i++)
     {
      double past=buy ? iLow(_Symbol,_Period,i) : iHigh(_Symbol,_Period,i);
      if(MathAbs(current-past)<=ARC_TOLERANCE_PTS*_Point)
         return(true);
     }
   return(false);
  }

bool IsMomentumTrigger(const bool buy)
  {
   double body=MathAbs(iClose(_Symbol,_Period,1)-iOpen(_Symbol,_Period,1));
   double range=iHigh(_Symbol,_Period,1)-iLow(_Symbol,_Period,1);
   if(range<=0.0)
      return(false);
   double ratio=body/range;
   if(buy && iClose(_Symbol,_Period,1)>iHigh(_Symbol,_Period,2) && ratio>MOMENTUM_BODY_MIN_RATIO) return(true);
   if(!buy && iClose(_Symbol,_Period,1)<iLow(_Symbol,_Period,2) && ratio>MOMENTUM_BODY_MIN_RATIO) return(true);
   return(false);
  }

bool HasLiquiditySweep(const bool buy)
  {
   double low1=iLow(_Symbol,_Period,1);
   double low2=iLow(_Symbol,_Period,2);
   double high1=iHigh(_Symbol,_Period,1);
   double high2=iHigh(_Symbol,_Period,2);
   double close1=iClose(_Symbol,_Period,1);
   if(buy)
      return(low1<low2 && close1>low2);
   return(high1>high2 && close1<high2);
  }

bool HasWickRejection(const bool buy)
  {
   double h=iHigh(_Symbol,_Period,1), l=iLow(_Symbol,_Period,1), o=iOpen(_Symbol,_Period,1), c=iClose(_Symbol,_Period,1);
   double range=h-l;
   if(range<=0.0)
      return(false);
   double upper=h-MathMax(o,c);
   double lower=MathMin(o,c)-l;
   if(buy)
      return(lower/range>=MIN_WICK_RATIO);
   return(upper/range>=MIN_WICK_RATIO);
  }

int CalculateScore(const bool buy,const ENUM_TREND_STATE trend)
  {
   int score=0;
   if((buy && trend!=TREND_DOWN) || (!buy && trend!=TREND_UP)) score++;
   if(IsArcTrigger(buy) || IsMomentumTrigger(buy)) score++;
   if(IsFlagPattern() || IsWedgeReversal()) score++;
   if(HasLiquiditySweep(buy)) score++;
   if(HasWickRejection(buy)) score++;
   return(score);
  }

//+------------------------------------------------------------------+
//| EXECUTION LAYER                                                 |
//+------------------------------------------------------------------+

double NormalizeVolume(const double lots)
  {
   double volMin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double volMax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(volStep<=0.0)
      return(0.0);
   double v=MathFloor(lots/volStep)*volStep;
   if(v<volMin) v=volMin;
   if(v>volMax) v=volMax;
   return(NormalizeDouble(v,2));
  }

double CalcVolumeByRisk(const double slDistPrice)
  {
   if(slDistPrice<=0.0)
      return(0.0);

   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tickSize<=0.0 || tickValue<=0.0)
      return(0.0);

   // Include slippage buffer: overestimate risk distance
   double bufferDist=slDistPrice+SLIPPAGE_BUFFER_POINTS*_Point;
   double riskMoney=AccountInfoDouble(ACCOUNT_EQUITY)*(Inp_RiskPercent/100.0);
   double lossPerLot=(bufferDist/tickSize)*tickValue;
   if(lossPerLot<=0.0)
      return(0.0);

   double volume=riskMoney/lossPerLot;
   // Apply loss-streak decay
   volume*=GetSizeMultiplier();
   return(NormalizeVolume(volume));
  }

double CalcVolumeByMargin(const double volume)
  {
   double safe=NormalizeVolume(volume);
   if(safe<=0.0)
      return(0.0);

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double minFree=equity*MIN_FREE_MARGIN_PCT/100.0;

   if(freeMargin<=minFree)
      return(0.0);

   ENUM_ORDER_TYPE orderType=ORDER_TYPE_BUY;
   double price=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(price<=0.0)
      return(0.0);

   double marginNeeded=0.0;
   if(!OrderCalcMargin(orderType,_Symbol,safe,price,marginNeeded) || marginNeeded<=0.0)
      return(0.0);

   double allowed=freeMargin-minFree;
   if(allowed<=0.0)
      return(0.0);

   if(marginNeeded<=allowed)
      return(safe);

   double scaled=safe*(allowed/marginNeeded);
   return(NormalizeVolume(scaled));
  }

//+------------------------------------------------------------------+
//| POSITION MANAGEMENT LAYER                                       |
//+------------------------------------------------------------------+

double GetBalancedSL(const bool buy,const double entry,const double atr)
  {
   int lookback=MathMax(3,SWING_LOOKBACK_BARS);
   double sl=0.0;

   if(buy)
     {
      int idx=iLowest(_Symbol,_Period,MODE_LOW,lookback,2);
      if(idx>=0)
         sl=iLow(_Symbol,_Period,idx)-SL_BUFFER_POINTS*_Point;
     }
   else
     {
      int idx=iHighest(_Symbol,_Period,MODE_HIGH,lookback,2);
      if(idx>=0)
         sl=iHigh(_Symbol,_Period,idx)+SL_BUFFER_POINTS*_Point;
     }

   if(sl<=0.0)
      sl=buy ? entry-atr*MIN_SL_ATR_MULT : entry+atr*MIN_SL_ATR_MULT;

   double minDist=atr*MIN_SL_ATR_MULT;
   double maxDist=atr*MAX_SL_ATR_MULT;
   double dist=MathAbs(entry-sl);

   if(dist<minDist)
      sl=buy ? entry-minDist : entry+minDist;
   else if(dist>maxDist)
      sl=buy ? entry-maxDist : entry+maxDist;

   return(sl);
  }

double GetTakeProfit(const bool buy,const double entry,const double sl)
  {
   double riskDist=MathAbs(entry-sl);
   if(riskDist<=0.0)
      return(0.0);

   double tpDist=riskDist*REWARD_MULTIPLIER;
   if(buy)
      return(entry+tpDist);
   return(entry-tpDist);
  }

bool IsClearReversalAgainstPosition(const bool positionIsBuy,const ENUM_TREND_STATE trend)
  {
   if(positionIsBuy)
     {
      bool oppositeTrend=(trend==TREND_DOWN);
      bool oppositeTrigger=(IsArcTrigger(false) || IsMomentumTrigger(false));
      bool oppositeQuality=(HasLiquiditySweep(false) && HasWickRejection(false));
      return(oppositeTrend && oppositeTrigger && oppositeQuality);
     }

   bool oppositeTrend=(trend==TREND_UP);
   bool oppositeTrigger=(IsArcTrigger(true) || IsMomentumTrigger(true));
   bool oppositeQuality=(HasLiquiditySweep(true) && HasWickRejection(true));
   return(oppositeTrend && oppositeTrigger && oppositeQuality);
  }

bool TrailPositions(const ENUM_TREND_STATE trend)
  {
   bool anyOpen=false;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=Inp_MagicNumber)
         continue;

      anyOpen=true;
      bool buy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);

      // Check for reversal close
      if(IsClearReversalAgainstPosition(buy,trend))
        {
         if(!ExtTrade.PositionClose(ticket))
            Log("Reversal close failed: "+(string)ExtTrade.ResultRetcode());
         else
            Log("Position closed on reversal signal");
         continue;
        }

      double atr=GetATR(0);
      if(atr<=0.0)
         continue;

      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

      // Breakeven after 1:1 achieved (guard against SL=0 / unset)
      double riskDist=(currentSL>0.0) ? MathAbs(entry-currentSL) : atr*MIN_SL_ATR_MULT;

      double progress=(buy) ? price-entry : entry-price;
      double beLevel=buy ? entry+riskDist*BREAKEVEN_ATR_MULT : entry-riskDist*BREAKEVEN_ATR_MULT;

      double newSL=currentSL;
      if(progress>=riskDist)
        {
         // 1:1 achieved -> trail from breakeven
         double trailLevel=buy ? price-atr*TRAIL_ATR_MULT : price+atr*TRAIL_ATR_MULT;
         if(buy)
           {
            if(trailLevel>beLevel) trailLevel=beLevel;
            if(trailLevel>newSL) newSL=trailLevel;
           }
         else
           {
            if(trailLevel<beLevel) trailLevel=beLevel;
            if(trailLevel<newSL || newSL==0.0) newSL=trailLevel;
           }
        }
      else if(newSL==0.0)
        {
         // No SL yet, set initial
         newSL=GetBalancedSL(buy,entry,atr);
        }

      bool improve=(buy && newSL>currentSL) || (!buy && (newSL<currentSL || currentSL==0.0));
      if(improve && newSL!=currentSL)
        {
         ExtTrade.SetExpertMagicNumber(Inp_MagicNumber);
         if(!ExtTrade.PositionModify(ticket,NormalizeDouble(newSL,_Digits),tp))
            Log("Trail modify failed: "+(string)ExtTrade.ResultRetcode());
        }
     }

   return(anyOpen);
  }

//+------------------------------------------------------------------+
//| Trade execution                                                  |
//+------------------------------------------------------------------+
bool ExecuteTrade(const bool buy,const int score,const string tag)
  {
   double atr=GetATR(1);
   if(atr<=0.0)
      return(false);

   double entry=buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(entry<=0.0)
      return(false);

   double sl=GetBalancedSL(buy,entry,atr);
   double tp=GetTakeProfit(buy,entry,sl);
   double slDist=MathAbs(entry-sl);
   if(slDist<=0.0 || tp<=0.0)
      return(false);

   double volume=CalcVolumeByRisk(slDist);
   if(volume<=0.0)
      return(false);

   volume=CalcVolumeByMargin(volume);
   if(volume<=0.0)
     {
      Log("Skip: insufficient free margin");
      return(false);
     }

   ExtTrade.SetExpertMagicNumber(Inp_MagicNumber);

   bool ok=false;
   if(buy)
      ok=ExtTrade.Buy(volume,_Symbol,0.0,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),tag);
   else
      ok=ExtTrade.Sell(volume,_Symbol,0.0,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),tag);

   if(!ok)
     {
      Log("Order failed. retcode="+(string)ExtTrade.ResultRetcode()+" msg="+ExtTrade.ResultRetcodeDescription());
      return(false);
     }

   Log((buy?"BUY":"SELL")+" opened. score="+(string)score+" vol="+DoubleToString(volume,2)+" sl="+DoubleToString(sl,_Digits)+" tp="+DoubleToString(tp,_Digits));
   g_state.dailyTrades++;
   SaveState();
   return(true);
  }

//+------------------------------------------------------------------+
//| Scan deal history for closed positions (updates risk state)      |
//+------------------------------------------------------------------+
void SyncStateFromHistory()
  {
   datetime now=TimeCurrent();
   if(now-g_lastHistoryScan<60)
      return;
   g_lastHistoryScan=now;

   // Scan last 30 days (avoid full account history on every tick)
   datetime from=now-30*86400;
   if(!HistorySelect(from,now))
      return;

   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0)
         continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol)
         continue;
      if(HistoryDealGetInteger(ticket,DEAL_MAGIC)!=Inp_MagicNumber)
         continue;
      long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT)
         continue;
      long type=HistoryDealGetInteger(ticket,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL)
         continue;

      double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
      if(profit>0)
        {
         g_state.consecutiveLosses=0;
         g_state.lossStreak=0;
        }
      else if(profit<0)
        {
         g_state.consecutiveLosses++;
         g_state.lossStreak++;
         if(g_state.consecutiveLosses>=MAX_CONSECUTIVE_LOSSES && g_state.cooldownUntil==0)
           {
            g_state.cooldownUntil=TimeCurrent()+COOLDOWN_HOURS*3600;
            Log("Cooldown triggered: "+string(g_state.consecutiveLosses)+" consecutive losses");
           }
        }
     }

   SaveState();
  }

//+------------------------------------------------------------------+
//| INIT / DEINIT                                                    |
//+------------------------------------------------------------------+

int OnInit(void)
  {
   if(Inp_ATR_Period<2 || Inp_MinScoreToTrade<1 || Inp_MinScoreToTrade>5)
      return(INIT_PARAMETERS_INCORRECT);
   if(Inp_RiskPercent<=0.0 || Inp_RiskPercent>10.0)
      return(INIT_PARAMETERS_INCORRECT);
   if(Inp_TrendLookback<20)
      return(INIT_PARAMETERS_INCORRECT);

   atrHandle=iATR(_Symbol,_Period,Inp_ATR_Period);
   if(atrHandle==INVALID_HANDLE)
      return(INIT_FAILED);

   ArraySetAsSeries(atrBuffer,true);

   // Load or init state
   if(!LoadState())
     {
      g_state.Init();
      Log("New state initialized");
     }
   else
     {
      Log("State loaded: peak="+DoubleToString(g_state.peakEquity,2)+
          " dayStart="+DoubleToString(g_state.dayStartEquity,2)+
          " consLoss="+(string)g_state.consecutiveLosses+
          " cooldown="+(string)g_state.cooldownUntil);
     }

   // Ensure folder exists
   FolderCreate(STATE_FOLDER,FILE_COMMON);

   ExtTrade.SetExpertMagicNumber(Inp_MagicNumber);

   Log("Initialized. Risk="+DoubleToString(Inp_RiskPercent,1)+
       "% ScoreMin="+(string)Inp_MinScoreToTrade+
       " ATR="+(string)Inp_ATR_Period+
       " Trend="+(string)Inp_TrendLookback);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(atrHandle!=INVALID_HANDLE)
     {
      IndicatorRelease(atrHandle);
      atrHandle=INVALID_HANDLE;
     }
   SaveState();
   Log("Deinitialized reason="+(string)reason);
  }

//+------------------------------------------------------------------+
//| ONTICK - Main loop                                               |
//+------------------------------------------------------------------+

void OnTick(void)
  {
   // === LAYER 1: State Maintenance ===
   CheckDayChange();
   UpdatePeakEquity();
   SyncStateFromHistory();

   // === LAYER 2: Safety Overrides ===
   if(IsFridayCloseTime())
     {
      if(CountOurPositions()>0)
         CloseAllOurPositions();
      return;
     }

   if(!RiskGateAllowsTrading())
      return;

   // === LAYER 3: Position Management (new bar only) ===
   if(!IsNewBar())
      return;

   ENUM_TREND_STATE trend=GetMarketStructureTrend();
   bool hasOpen=TrailPositions(trend);
   if(hasOpen)
      return;

   // === LAYER 4: Signal Generation ===
   int scoreBuy=CalculateScore(true,trend);
   int scoreSell=CalculateScore(false,trend);

   Log("trend="+(string)trend+" buyScore="+(string)scoreBuy+" sellScore="+(string)scoreSell);

   bool strongReversalBuy=(trend==TREND_DOWN && HasLiquiditySweep(true) && HasWickRejection(true) && (IsArcTrigger(true)||IsMomentumTrigger(true)));
   bool strongReversalSell=(trend==TREND_UP && HasLiquiditySweep(false) && HasWickRejection(false) && (IsArcTrigger(false)||IsMomentumTrigger(false)));

   // === LAYER 5: Entry ===
   if(scoreBuy>=Inp_MinScoreToTrade && (trend!=TREND_DOWN || strongReversalBuy))
      ExecuteTrade(true,scoreBuy,"Falcon Buy");
   else if(scoreSell>=Inp_MinScoreToTrade && (trend!=TREND_UP || strongReversalSell))
      ExecuteTrade(false,scoreSell,"Falcon Sell");
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
