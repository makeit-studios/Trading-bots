// First-sight M5 Simple Trender arrow model for XAUUSD.
// A live arrow is actionable on its first observed tick and may later disappear.
#property strict
#property version "1.20"
#include <Trade/Trade.mqh>

enum EArrowFilter
  {
   ARROW_ONLY=0,
   ARROW_H4_M15_ALIGNED=1,
   ARROW_M15_BAND=2,
   ARROW_M15_H1_BAND=3,
   ARROW_M15_H2_BAND=4,
   ARROW_M15_H4_BAND=5,
   ARROW_M15_H1_H2_H4_BAND=6
  };
input group "Live M5 arrow strategy controls"
input EArrowFilter InpFilter=ARROW_ONLY;
input bool InpTradingEnabled=true;
input double InpRiskPct=1.0;
input double InpMaxCombinedRiskPct=4.0;
input double InpTargetR=1.0;
input ulong InpMagic=26102305;
input int InpMaxDeviationPoints=20;

#define MAIN_BARS 900
#define SIGNAL_BARS 1200
#define MAIN_PIVOT 21
#define SIGNAL_PIVOT 3
#define EMA_LOW_LENGTH 26
#define VWAP_EMA_LENGTH 13
#define EMA_LONG_LENGTH 200
#define RECENT_ARROW_COUNT 24
#define RECENT_PIVOT_COUNT 8
#define EVENT_MARK_LIMIT 50

enum EDir { DIR_DOWN=-1,DIR_NONE=0,DIR_UP=1 };
struct PivotMark
  {
   ENUM_TIMEFRAMES tf;
   datetime pivotTime,confirmTime;
   double price;
   int type;
   string tag;
  };
struct StructureState
  {
   int dir,pending,breakDir;
   datetime breakTime;
   double lastHigh,lastLow,priorHigh,priorLow,breakLevel;
   string lastEvent;
  };
struct ArrowMark { datetime time,confirmTime; double price; int dir; };
struct ExitIntent { ulong positionId; string why; };

CTrade g_trade;
MqlRates g_h4[],g_m15[],g_m5[],g_liveBar;
PivotMark g_marks[];
ArrowMark g_arrows[];
ExitIntent g_exitIntents[];
StructureState g_main,g_internal;
double g_emaLow[],g_vwapSmooth[];
double g_prevEmaLow=0,g_prevSmooth=0,g_prevLongEMA=0,g_prevPV=0,g_prevVol=0;
double g_liveEma=0,g_liveSmooth=0,g_liveLong=0;
int g_prevDay=0,g_confirmedArrow=0,g_liveArrow=0;
int g_m15Band=0,g_h1Band=0,g_h2Band=0,g_h4Band=0;
datetime g_lastM5=0,g_lastM15=0,g_lastH4=0,g_pendingBar=0,g_pendingSignal=0,g_lastPanel=0;
int g_pendingDir=0;
double g_pendingStop=0;
int g_drawnLiveArrow=0;
datetime g_drawnLiveBar=0;
bool g_pending=false,g_hedging=false,g_supported=false;
string g_reason="Starting",g_prefix="LA5_";
ulong g_eventDeals[];
datetime g_signalMarks[];

bool CanDrawChart() { return !MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE); }
string DirText(const int dir) { return dir>0?"UP":dir<0?"DOWN":"UNCLEAR"; }
string FilterText()
  {
   switch(InpFilter)
     {
      case ARROW_ONLY: return "ARROW ONLY";
      case ARROW_H4_M15_ALIGNED: return "H4 + M15 STRUCTURE";
      case ARROW_M15_BAND: return "M15 BAND";
      case ARROW_M15_H1_BAND: return "M15 + H1 BANDS";
      case ARROW_M15_H2_BAND: return "M15 + H2 BANDS";
      case ARROW_M15_H4_BAND: return "M15 + H4 BANDS";
      case ARROW_M15_H1_H2_H4_BAND: return "M15 + H1/H2/H4 BANDS";
     }
   return "UNKNOWN";
  }
string TimeText(const datetime value) { return TimeToString(value,TIME_DATE|TIME_MINUTES); }

void LogEvent(const string kind,const string detail)
  {
   Print("LA5 ",kind," ",detail);
   int file=FileOpen("LiveArrowM5EA_events.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(file==INVALID_HANDLE) return;
   FileSeek(file,0,SEEK_END);
   FileWrite(file,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),_Symbol,kind,detail);
   FileClose(file);
  }
void SetReason(const string why)
  {
   if(g_reason==why) return;
   g_reason=why;
   LogEvent("STATE",why);
  }
int LoadRates(const ENUM_TIMEFRAMES tf,const int count,MqlRates &rates[])
  {
   ArrayFree(rates);
   ArraySetAsSeries(rates,false);
   return CopyRates(_Symbol,tf,0,count,rates);
  }
bool IsPivotHigh(const MqlRates &rates[],const int p,const int length)
  {
   for(int j=1;j<=length;j++)
      if(rates[p-j].high>=rates[p].high || rates[p+j].high>rates[p].high) return false;
   return true;
  }
bool IsPivotLow(const MqlRates &rates[],const int p,const int length)
  {
   for(int j=1;j<=length;j++)
      if(rates[p-j].low<=rates[p].low || rates[p+j].low<rates[p].low) return false;
   return true;
  }
void AddMark(const ENUM_TIMEFRAMES tf,const datetime pivot,const datetime confirmed,
             const double price,const int type,const string tag)
  {
   int size=ArraySize(g_marks);
   ArrayResize(g_marks,size+1);
   g_marks[size].tf=tf; g_marks[size].pivotTime=pivot;
   g_marks[size].confirmTime=confirmed; g_marks[size].price=price;
   g_marks[size].type=type; g_marks[size].tag=tag;
  }
void BuildStructure(const MqlRates &rates[],const int n,const int length,
                    const ENUM_TIMEFRAMES tf,StructureState &state)
  {
   ZeroMemory(state);
   state.lastEvent="waiting for swings";
   if(n<2*length+5) return;
   int highClass=0,lowClass=0,upBreaks=0,downBreaks=0;
   for(int i=2*length;i<n-1;i++)
     {
      int p=i-length;
      bool newPivot=false;
      if(IsPivotHigh(rates,p,length))
        {
         newPivot=true;
         state.priorHigh=state.lastHigh; state.lastHigh=rates[p].high;
         highClass=state.priorHigh>0?(state.lastHigh>state.priorHigh?1:-1):0;
         AddMark(tf,rates[p].time,rates[i+1].time,state.lastHigh,1,
                 highClass>0?"HH":highClass<0?"LH":"H");
        }
      if(IsPivotLow(rates,p,length))
        {
         newPivot=true;
         state.priorLow=state.lastLow; state.lastLow=rates[p].low;
         lowClass=state.priorLow>0?(state.lastLow>state.priorLow?1:-1):0;
         AddMark(tf,rates[p].time,rates[i+1].time,state.lastLow,-1,
                 lowClass>0?"HL":lowClass<0?"LL":"L");
        }
      if(newPivot && highClass*lowClass<0) state.dir=DIR_NONE;
      if(state.dir==DIR_NONE && highClass>0 && lowClass>0 &&
         (state.pending==DIR_NONE || state.pending==DIR_UP))
         { state.dir=DIR_UP; state.pending=DIR_NONE; }
      if(state.dir==DIR_NONE && highClass<0 && lowClass<0 &&
         (state.pending==DIR_NONE || state.pending==DIR_DOWN))
         { state.dir=DIR_DOWN; state.pending=DIR_NONE; }
      // The break belongs to the closed bar i; its event is available at i+1.
      if(state.lastHigh>0 && rates[i].close>state.lastHigh && rates[i-1].close<=state.lastHigh)
        {
         state.breakDir=DIR_UP; state.breakTime=rates[i].time;
         state.breakLevel=state.lastHigh;
         state.lastEvent=state.dir<0?"bullish CHoCH":"bullish BOS";
         AddMark(tf,rates[i].time,rates[i+1].time,state.breakLevel,2,state.lastEvent);
         upBreaks++; downBreaks=0;
         if(tf!=PERIOD_H4 || state.dir>=0 ||
            (highClass>0 && lowClass>0 && upBreaks>=2))
            { state.dir=DIR_UP; state.pending=DIR_NONE; }
         else { state.pending=DIR_UP; state.dir=DIR_NONE; }
        }
      if(state.lastLow>0 && rates[i].close<state.lastLow && rates[i-1].close>=state.lastLow)
        {
         state.breakDir=DIR_DOWN; state.breakTime=rates[i].time;
         state.breakLevel=state.lastLow;
         state.lastEvent=state.dir>0?"bearish CHoCH":"bearish BOS";
         AddMark(tf,rates[i].time,rates[i+1].time,state.breakLevel,-2,state.lastEvent);
         downBreaks++; upBreaks=0;
         if(tf!=PERIOD_H4 || state.dir<=0 ||
            (highClass<0 && lowClass<0 && downBreaks>=2))
            { state.dir=DIR_DOWN; state.pending=DIR_NONE; }
         else { state.pending=DIR_DOWN; state.dir=DIR_NONE; }
        }
     }
  }

int SessionDay(const datetime barTime)
  {
   MqlDateTime value; TimeToStruct(barTime,value);
   return value.year*10000+value.mon*100+value.day;
  }
int ArrowForBar(const double close,const double previousClose,
                const double emaLow,const double smoothedVWAP)
  {
   if(close>emaLow && previousClose<smoothedVWAP && close>smoothedVWAP) return DIR_UP;
   if(close<emaLow && previousClose>smoothedVWAP && close<smoothedVWAP) return DIR_DOWN;
   return DIR_NONE;
  }
int ClosedBandDirection(const ENUM_TIMEFRAMES tf)
  {
   // Start at shift 1. The current higher-timeframe candle is never a filter input.
   MqlRates closed[];
   ArraySetAsSeries(closed,false);
   int n=CopyRates(_Symbol,tf,1,200,closed);
   if(n<EMA_LOW_LENGTH+2) return DIR_NONE;
   double alpha=2.0/(EMA_LOW_LENGTH+1.0);
   double ema=closed[0].low;
   for(int i=1;i<n;i++) ema=alpha*closed[i].low+(1.0-alpha)*ema;
   return closed[n-1].close>ema?DIR_UP:
          closed[n-1].close<ema?DIR_DOWN:DIR_NONE;
  }
void ComputeTrender(const MqlRates &rates[],const int n)
  {
   g_confirmedArrow=0; g_liveArrow=0;
   ArrayFree(g_arrows);
   ArrayResize(g_emaLow,n); ArrayResize(g_vwapSmooth,n);
   if(n<EMA_LONG_LENGTH+3) return;
   const double emaAlpha=2.0/(EMA_LOW_LENGTH+1.0);
   const double vwapAlpha=2.0/(VWAP_EMA_LENGTH+1.0);
   const double longAlpha=2.0/(EMA_LONG_LENGTH+1.0);
   double ema=0,longEMA=0,smoothed=0,sumPV=0,sumVol=0;
   int priorDay=0;
   for(int i=0;i<n;i++)
     {
      int day=SessionDay(rates[i].time);
      if(day!=priorDay) { sumPV=0; sumVol=0; priorDay=day; }
      double volume=MathMax(1.0,(double)rates[i].tick_volume);
      double typical=(rates[i].high+rates[i].low+rates[i].close)/3.0;
      sumPV+=typical*volume; sumVol+=volume;
      double vwap=sumPV/sumVol;
      ema=i==0?rates[i].low:emaAlpha*rates[i].low+(1-emaAlpha)*ema;
      longEMA=i==0?rates[i].close:longAlpha*rates[i].close+(1-longAlpha)*longEMA;
      smoothed=i==0?vwap:vwapAlpha*vwap+(1-vwapAlpha)*smoothed;
      g_emaLow[i]=ema; g_vwapSmooth[i]=smoothed;
      if(i>0)
        {
         // The supplied Pine script compares close[1] with the current smoothed VWAP.
         int dir=ArrowForBar(rates[i].close,rates[i-1].close,ema,smoothed);
         if(i==n-2) g_confirmedArrow=dir;
         if(i<n-1 && dir!=0 && i>=n-RECENT_ARROW_COUNT)
           {
            int count=ArraySize(g_arrows); ArrayResize(g_arrows,count+1);
            g_arrows[count].time=rates[i].time;
            g_arrows[count].confirmTime=rates[i+1].time;
            g_arrows[count].price=dir>0?rates[i].low:rates[i].high;
            g_arrows[count].dir=dir;
           }
        }
      if(i==n-2)
        {
         g_prevEmaLow=ema; g_prevSmooth=smoothed; g_prevLongEMA=longEMA;
         g_prevPV=sumPV; g_prevVol=sumVol; g_prevDay=day;
        }
     }
   double volume=MathMax(1.0,(double)rates[n-1].tick_volume);
   double pv=SessionDay(rates[n-1].time)==g_prevDay?g_prevPV:0;
   double vol=SessionDay(rates[n-1].time)==g_prevDay?g_prevVol:0;
   double typical=(rates[n-1].high+rates[n-1].low+rates[n-1].close)/3.0;
   double vwap=(pv+typical*volume)/(vol+volume);
   g_liveEma=emaAlpha*rates[n-1].low+(1-emaAlpha)*g_prevEmaLow;
   g_liveSmooth=vwapAlpha*vwap+(1-vwapAlpha)*g_prevSmooth;
   g_liveLong=longAlpha*rates[n-1].close+(1-longAlpha)*g_prevLongEMA;
   g_liveArrow=ArrowForBar(rates[n-1].close,rates[n-2].close,g_liveEma,g_liveSmooth);
  }
void UpdateLiveArrow()
  {
   int n=ArraySize(g_m5); if(n<2 || g_prevVol<=0) return;
   MqlRates live[];
   if(CopyRates(_Symbol,PERIOD_M5,0,1,live)!=1) return;
   MqlRates bar=live[0];
   g_liveBar=bar;
   double volume=MathMax(1.0,(double)bar.tick_volume);
   double pv=SessionDay(bar.time)==g_prevDay?g_prevPV:0;
   double vol=SessionDay(bar.time)==g_prevDay?g_prevVol:0;
   double typical=(bar.high+bar.low+bar.close)/3.0;
   double vwap=(pv+typical*volume)/(vol+volume);
   g_liveEma=2.0/(EMA_LOW_LENGTH+1.0)*bar.low+
             (1-2.0/(EMA_LOW_LENGTH+1.0))*g_prevEmaLow;
   g_liveSmooth=2.0/(VWAP_EMA_LENGTH+1.0)*vwap+
                (1-2.0/(VWAP_EMA_LENGTH+1.0))*g_prevSmooth;
   g_liveArrow=ArrowForBar(bar.close,g_m5[n-2].close,g_liveEma,g_liveSmooth);
   if(!CanDrawChart() || (g_drawnLiveBar==bar.time && g_drawnLiveArrow==g_liveArrow)) return;
   g_drawnLiveBar=bar.time; g_drawnLiveArrow=g_liveArrow;
   string name=g_prefix+"DYN_LIVE_ARROW";
   ObjectDelete(0,name);
   if(g_liveArrow!=0)
     {
      ObjectCreate(0,name,g_liveArrow>0?OBJ_ARROW_UP:OBJ_ARROW_DOWN,0,
                   bar.time,g_liveArrow>0?bar.low:bar.high);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrSilver);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,"M5 live arrow: traded at first sight; may disappear before close");
     }
  }

bool RefreshAnalysis()
  {
   int h=LoadRates(PERIOD_H4,MAIN_BARS,g_h4);
   int m15=LoadRates(PERIOD_M15,MAIN_BARS,g_m15);
   int m5=LoadRates(PERIOD_M5,SIGNAL_BARS,g_m5);
   if(m5<EMA_LONG_LENGTH+3 || m15<2*SIGNAL_PIVOT+5 || h<2*MAIN_PIVOT+5)
     { SetReason("waiting for H4/M15 structure and M5 arrow history"); return false; }
   ArrayFree(g_marks);
   BuildStructure(g_h4,h,MAIN_PIVOT,PERIOD_H4,g_main);
   BuildStructure(g_m15,m15,SIGNAL_PIVOT,PERIOD_M15,g_internal);
   ComputeTrender(g_m5,m5);
   g_m15Band=ClosedBandDirection(PERIOD_M15);
   g_h1Band=ClosedBandDirection(PERIOD_H1);
   g_h2Band=ClosedBandDirection(PERIOD_H2);
   g_h4Band=ClosedBandDirection(PERIOD_H4);
   return true;
  }

double ReservedRiskMoney()
  {
   double risk=0,loss=0;
   double full=AccountInfoDouble(ACCOUNT_EQUITY)*InpMaxCombinedRiskPct/100.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      double sl=PositionGetDouble(POSITION_SL);
      if(sl<=0) return full;
      int type=(int)PositionGetInteger(POSITION_TYPE);
      if(!OrderCalcProfit(type==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,
                          _Symbol,PositionGetDouble(POSITION_VOLUME),
                          PositionGetDouble(POSITION_PRICE_OPEN),sl,loss)) return full;
      risk+=MathMax(0.0,-loss);
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      double sl=OrderGetDouble(ORDER_SL);
      if(sl<=0) return full;
      int type=(int)OrderGetInteger(ORDER_TYPE);
      bool buy=(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP ||
                type==ORDER_TYPE_BUY_STOP_LIMIT);
      if(!OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,
                          OrderGetDouble(ORDER_VOLUME_CURRENT),
                          OrderGetDouble(ORDER_PRICE_OPEN),sl,loss)) return full;
      risk+=MathMax(0.0,-loss);
     }
   return risk;
  }
int VolumeDigits(double step)
  { int digits=0; while(digits<8 && MathAbs(step-MathRound(step))>1e-9) { step*=10; digits++; } return digits; }
double SizeForRisk(const int dir,const double entry,const double sl,const double money)
  {
   double oneLot=0;
   if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,1.0,entry,sl,oneLot)
      || oneLot>=0) return 0;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0 || minLot<=0 || maxLot<=0) return 0;
   double size=MathFloor(money/(-oneLot)/step+1e-9)*step;
   size=MathMin(size,MathFloor(maxLot/step+1e-9)*step);
   size=NormalizeDouble(size,VolumeDigits(step));
   return size>=minLot?size:0;
  }
bool MarketFillPolicy(ENUM_ORDER_TYPE_FILLING &policy)
  {
   int flags=(int)SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((flags&SYMBOL_FILLING_FOK)!=0) { policy=ORDER_FILLING_FOK; return true; }
   if((flags&SYMBOL_FILLING_IOC)!=0) { policy=ORDER_FILLING_IOC; return true; }
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE)!=SYMBOL_TRADE_EXECUTION_MARKET)
      { policy=ORDER_FILLING_RETURN; return true; }
   return false;
  }
bool OwnPosition(const ulong ticket)
  {
   return ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
          (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic;
  }
int OwnDirectionCount(const int dir)
  {
   int count=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(!OwnPosition(ticket)) continue;
      int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?DIR_UP:DIR_DOWN;
      if(side==dir) count++;
     }
   return count;
  }
bool AnyExternalOpposite(const int dir)
  {
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?DIR_UP:DIR_DOWN;
      if(side==-dir && (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) return true;
     }
   return false;
  }
void RememberExitIntent(const ulong positionId,const string why)
  {
   for(int i=0;i<ArraySize(g_exitIntents);i++)
      if(g_exitIntents[i].positionId==positionId) { g_exitIntents[i].why=why; return; }
   int count=ArraySize(g_exitIntents); ArrayResize(g_exitIntents,count+1);
   g_exitIntents[count].positionId=positionId; g_exitIntents[count].why=why;
  }
string ExitIntentFor(const ulong positionId)
  {
   for(int i=0;i<ArraySize(g_exitIntents);i++)
      if(g_exitIntents[i].positionId==positionId && g_exitIntents[i].why!="")
         return g_exitIntents[i].why;
   return "server exit";
  }
void ClearExitIntent(const ulong positionId)
  {
   for(int i=0;i<ArraySize(g_exitIntents);i++)
      if(g_exitIntents[i].positionId==positionId)
        { g_exitIntents[i].why=""; return; }
  }
bool CloseTicket(const ulong ticket,const string why)
  {
   if(!PositionSelectByTicket(ticket)) return true;
   if(!OwnPosition(ticket)) return true;
   ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   RememberExitIntent(positionId,why);
   bool sent=g_trade.PositionClose(ticket,(ulong)InpMaxDeviationPoints);
   uint code=g_trade.ResultRetcode();
   if(!sent || code!=TRADE_RETCODE_DONE || PositionSelectByTicket(ticket))
     {
      ClearExitIntent(positionId);
      SetReason("close blocked #"+IntegerToString((long)ticket)+": "+why+
                " retcode="+IntegerToString((int)code)+" "+g_trade.ResultRetcodeDescription());
      return false;
     }
   LogEvent("EXIT_REQUEST","#"+IntegerToString((long)ticket)+" "+why);
   return true;
  }
bool CloseOppositeOwn(const int newDir)
  {
   bool allClosed=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!OwnPosition(ticket)) continue;
      int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?DIR_UP:DIR_DOWN;
      if(side==-newDir && !CloseTicket(ticket,"opposite first-sight M5 arrow")) allClosed=false;
     }
   return allClosed && OwnDirectionCount(-newDir)==0;
  }
string SignalKey(const datetime candle,const int dir)
  {
   // One first-sight decision per M5 candle, even if its live arrow flips later.
   return "LA5_"+IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+
          IntegerToString((long)InpMagic)+"_"+IntegerToString((long)candle);
  }
bool SignalHandled(const datetime candle,const int dir)
  { return GlobalVariableCheck(SignalKey(candle,dir)); }
void MarkSignalHandled(const datetime candle,const int dir)
  { GlobalVariableSet(SignalKey(candle,dir),(double)TimeCurrent()); }
bool AlignmentPasses(const EArrowFilter filter,const int dir,
                     const int mainDir,const int internalDir,
                     const int m15Band,const int h1Band,
                     const int h2Band,const int h4Band)
  {
   if(filter==ARROW_ONLY) return true;
   if(filter==ARROW_H4_M15_ALIGNED) return mainDir==dir && internalDir==dir;
   if(m15Band!=dir) return false;
   if(filter==ARROW_M15_BAND) return true;
   if(filter==ARROW_M15_H1_BAND) return h1Band==dir;
   if(filter==ARROW_M15_H2_BAND) return h2Band==dir;
   if(filter==ARROW_M15_H4_BAND) return h4Band==dir;
   if(filter==ARROW_M15_H1_H2_H4_BAND)
      return h1Band==dir && h2Band==dir && h4Band==dir;
   return false;
  }
bool FilterPasses(const int dir)
  { return AlignmentPasses(InpFilter,dir,g_main.dir,g_internal.dir,
                           g_m15Band,g_h1Band,g_h2Band,g_h4Band); }
string BandStates()
  { return "M15="+DirText(g_m15Band)+" H1="+DirText(g_h1Band)+
           " H2="+DirText(g_h2Band)+" H4="+DirText(g_h4Band); }
bool CheckSignalPrices(const int dir,const double entry,const double sl,string &why)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) { why="no quote"; return false; }
   if(dir*(entry-sl)<=0) { why="signal candle stop is on wrong side"; return false; }
   double distance=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(dir>0?sl>=tick.bid-distance:sl<=tick.ask+distance)
      { why="signal candle stop violates broker distance"; return false; }
   return true;
  }
double TargetPrice(const int dir,const double entry,const double sl)
  {
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=_Point;
   double raw=entry+dir*InpTargetR*MathAbs(entry-sl);
   double steps=dir>0?MathCeil(raw/tick-1e-9):MathFloor(raw/tick+1e-9);
   return NormalizeDouble(steps*tick,_Digits);
  }
bool OpenArrowTrade(const int dir,const datetime candle,const double sl)
  {
   if(!g_supported) { SetReason("skip: XAUUSD symbol required"); return false; }
   if(!g_hedging) { SetReason("skip: hedging account required for separate entries"); return false; }
   if(AnyExternalOpposite(dir))
      { SetReason("skip: another strategy holds an opposite XAUUSD position"); return false; }
   if(OwnDirectionCount(-dir)>0)
      { SetReason("skip: opposite position still open; no hedge permitted"); return false; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) { SetReason("skip: no quote"); return false; }
   double entry=NormalizeDouble(dir>0?tick.ask:tick.bid,_Digits);
   string why="";
   if(!CheckSignalPrices(dir,entry,sl,why)) { SetReason("skip: "+why); return false; }
   double target=TargetPrice(dir,entry,sl);
   double distance=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(dir*(target-entry)<=0 ||
      (dir>0?target<=tick.bid+distance:target>=tick.ask-distance))
      { SetReason("skip: exact R target violates broker distance"); return false; }
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double budget=MathMin(equity*InpRiskPct/100.0,
                         equity*InpMaxCombinedRiskPct/100.0-ReservedRiskMoney());
   if(budget<=0) { SetReason("skip: 4% combined XAUUSD risk cap"); return false; }
   double worstEntry=entry+dir*InpMaxDeviationPoints*_Point;
   double volume=SizeForRisk(dir,worstEntry,sl,budget);
   if(volume<=0) { SetReason("skip: minimum lot exceeds remaining risk budget"); return false; }
   double loss=0;
   if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,
                       volume,worstEntry,sl,loss) || loss>=0 || -loss>budget+0.01)
      { SetReason("skip: calculated stop risk exceeds budget"); return false; }
   double margin=0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,margin)
      || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      { SetReason("skip: insufficient free margin"); return false; }
   ENUM_ORDER_TYPE_FILLING filling=ORDER_FILLING_FOK;
   if(!MarketFillPolicy(filling)) { SetReason("skip: no market fill policy"); return false; }
   MqlTradeRequest request={}; MqlTradeCheckResult check={};
   request.action=TRADE_ACTION_DEAL; request.symbol=_Symbol;
   request.magic=InpMagic; request.volume=volume; request.price=entry;
   request.sl=sl; request.tp=target;
   request.type=dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   request.type_filling=filling; request.deviation=InpMaxDeviationPoints;
   request.comment="LA5:"+IntegerToString((long)candle)+":"+(dir>0?"B":"S");
   ResetLastError();
   bool checked=OrderCheck(request,check);
   int error=GetLastError();
   if(!checked || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE &&
                   check.retcode!=TRADE_RETCODE_PLACED))
     {
      SetReason("skip: OrderCheck retcode="+IntegerToString((int)check.retcode)+
                " error="+IntegerToString(error)+" "+check.comment);
      return false;
     }
   MqlTradeResult result={}; bool sent=OrderSend(request,result);
   if(!sent || (result.retcode!=TRADE_RETCODE_DONE &&
                result.retcode!=TRADE_RETCODE_DONE_PARTIAL &&
                result.retcode!=TRADE_RETCODE_PLACED))
     {
      SetReason("skip: server rejected arrow order retcode="+
                IntegerToString((int)result.retcode)+" "+result.comment);
      return false;
     }
   LogEvent("ORDER","first-sight "+string(dir>0?"BUY":"SELL")+
            " M5="+TimeText(candle)+" entry="+DoubleToString(entry,_Digits)+
            " exact SL="+DoubleToString(sl,_Digits)+
            " target="+DoubleToString(target,_Digits)+
            " R="+DoubleToString(InpTargetR,1)+" lots="+DoubleToString(volume,2)+
            " filter="+FilterText()+" bands "+BandStates()+
            " H4 structure="+DirText(g_main.dir)+
            " M15 structure="+DirText(g_internal.dir));
   SetReason("entered "+string(dir>0?"BUY":"SELL")+
             " on first-sight M5 arrow; fixed target or stop or reversal");
   return true;
  }
void ProcessPendingSignal()
  {
   if(!g_pending) return;
   if(iTime(_Symbol,PERIOD_M5,0)!=g_pendingBar)
     { LogEvent("SKIP","signal expired before reversal could complete"); g_pending=false; return; }
   int dir=g_pendingDir;
   datetime candle=g_pendingSignal;
   if(OwnDirectionCount(-dir)>0)
     {
      if(!CloseOppositeOwn(dir))
        { SetReason("reversal waiting: opposite position did not close"); return; }
      LogEvent("REVERSE","all old-side positions closed before new "+string(dir>0?"BUY":"SELL")+" evaluation");
     }
   // A disallowed reversal still closes the old side, as agreed.
   if(!FilterPasses(dir))
     {
      string why="skip new "+string(dir>0?"BUY":"SELL")+
                 ": "+FilterText()+" disagrees; "+BandStates()+
                 "; H4 structure="+DirText(g_main.dir)+
                 " M15 structure="+DirText(g_internal.dir)+
                 "; old side closed";
      LogEvent("SKIP",TimeText(candle)+" "+why);
      SetReason(why);
      g_pending=false; return;
     }
   if(!InpTradingEnabled)
     {
      string why="signal "+string(dir>0?"BUY":"SELL")+" observed; new entries disabled";
      LogEvent("SKIP",TimeText(candle)+" "+why);
      SetReason(why);
      g_pending=false; return;
     }
   if(!OpenArrowTrade(dir,candle,g_pendingStop))
      LogEvent("SKIP",TimeText(candle)+" "+g_reason);
   g_pending=false;
  }

void DrawLabel(const string name,const datetime when,const double price,
               const string label,const color shade,const string tip="")
  {
   if(!ObjectCreate(0,name,OBJ_TEXT,0,when,price)) return;
   ObjectSetString(0,name,OBJPROP_TEXT,label);
   ObjectSetInteger(0,name,OBJPROP_COLOR,shade);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip==""?label:tip);
  }
void DrawLevel(const string name,const double price,const color shade,
               const ENUM_LINE_STYLE style,const string tip,const int backBars=16)
  {
   if(price<=0) return;
   datetime left=TimeCurrent()-PeriodSeconds(PERIOD_M5)*backBars;
   datetime right=TimeCurrent()+PeriodSeconds(PERIOD_M5);
   if(!ObjectCreate(0,name,OBJ_TREND,0,left,price,right,price)) return;
   ObjectSetInteger(0,name,OBJPROP_COLOR,shade);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip+" @ "+DoubleToString(price,_Digits));
  }
void DrawTrenderLines()
  {
   int n=ArraySize(g_m5);
   if(n<2 || ArraySize(g_emaLow)!=n) return;
   int begin=MathMax(1,n-18);
   for(int i=begin;i<n-1;i++)
     {
      string id=g_prefix+"DYN_EMA_"+IntegerToString(i);
      ObjectCreate(0,id,OBJ_TREND,0,g_m5[i-1].time,g_emaLow[i-1],
                   g_m5[i].time,g_emaLow[i]);
      ObjectSetInteger(0,id,OBJPROP_COLOR,clrRoyalBlue);
      ObjectSetInteger(0,id,OBJPROP_RAY_RIGHT,false);
      ObjectSetString(0,id,OBJPROP_TOOLTIP,"Simple Trender EMA 26 of M5 lows");
      id=g_prefix+"DYN_VWAP_"+IntegerToString(i);
      ObjectCreate(0,id,OBJ_TREND,0,g_m5[i-1].time,g_vwapSmooth[i-1],
                   g_m5[i].time,g_vwapSmooth[i]);
      ObjectSetInteger(0,id,OBJPROP_COLOR,clrViolet);
      ObjectSetInteger(0,id,OBJPROP_RAY_RIGHT,false);
      ObjectSetString(0,id,OBJPROP_TOOLTIP,"EMA 13 of broker-day M5 VWAP approximation");
     }
   DrawLabel(g_prefix+"DYN_EMA_NAME",g_m5[n-1].time,g_emaLow[n-2],
             "EMA 26 LOW",clrRoyalBlue);
   DrawLabel(g_prefix+"DYN_VWAP_NAME",g_m5[n-1].time,g_vwapSmooth[n-2],
             "VWAP EMA 13",clrViolet);
  }
void DrawPivots()
  {
   int h4Count=0,m15Count=0;
   for(int i=ArraySize(g_marks)-1;i>=0;i--)
     {
      PivotMark mark=g_marks[i];
      if(mark.tf==PERIOD_H4) { if(h4Count++>=2) continue; }
      else { if(m15Count++>=RECENT_PIVOT_COUNT) continue; }
      string id=g_prefix+"DYN_PIVOT_"+IntegerToString((long)mark.pivotTime)+"_"+
                IntegerToString((int)mark.tf)+"_"+IntegerToString(mark.type);
      string tf=mark.tf==PERIOD_H4?"H4":"M15";
      color shade=mark.tf==PERIOD_H4?clrOrange:clrDodgerBlue;
      string label=tf+" "+mark.tag;
      DrawLabel(id,mark.confirmTime,mark.price,label,shade,
                label+" pivot "+TimeText(mark.pivotTime)+
                " confirmed "+TimeText(mark.confirmTime));
     }
  }
void DrawArrows()
  {
   for(int i=0;i<ArraySize(g_arrows);i++)
     {
      ArrowMark arrow=g_arrows[i];
      string id=g_prefix+"DYN_ARROW_"+IntegerToString((long)arrow.time);
      ObjectCreate(0,id,arrow.dir>0?OBJ_ARROW_UP:OBJ_ARROW_DOWN,0,
                   arrow.time,arrow.price);
      ObjectSetInteger(0,id,OBJPROP_COLOR,arrow.dir>0?clrLime:clrRed);
      ObjectSetString(0,id,OBJPROP_TOOLTIP,
                      "M5 "+string(arrow.dir>0?"BUY":"SELL")+
                      " arrow still present at close "+TimeText(arrow.confirmTime));
     }
   int n=ArraySize(g_m5);
   if(n>0 && g_liveArrow!=0)
     {
      string id=g_prefix+"DYN_LIVE_ARROW";
      ObjectCreate(0,id,g_liveArrow>0?OBJ_ARROW_UP:OBJ_ARROW_DOWN,0,
                   g_m5[n-1].time,g_liveArrow>0?g_m5[n-1].low:g_m5[n-1].high);
      ObjectSetInteger(0,id,OBJPROP_COLOR,clrSilver);
      ObjectSetString(0,id,OBJPROP_TOOLTIP,
                      "M5 live arrow; traded at first sight; may disappear before close");
     }
  }
void DrawPositions()
  {
   int labelIndex=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(!OwnPosition(ticket)) continue;
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?DIR_UP:DIR_DOWN;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      string id=g_prefix+"DYN_POS_"+IntegerToString((long)ticket);
      string label=(dir>0?"BUY":"SELL")+" #"+IntegerToString((long)ticket);
      DrawLevel(id+"_ENTRY",entry,clrAqua,STYLE_SOLID,label+" entry",10);
      DrawLevel(id+"_STOP",sl,clrTomato,STYLE_DASH,label+" exact candle stop",10);
      DrawLevel(id+"_TARGET",tp,clrGold,STYLE_DOT,label+" fixed "+
                DoubleToString(InpTargetR,1)+"R target",10);
      datetime x=TimeCurrent()-PeriodSeconds(PERIOD_M5)*(8+labelIndex*2);
      DrawLabel(id+"_NAME",x,entry,label,clrAqua);
      labelIndex++;
     }
  }
void RenderChart()
  {
   if(!CanDrawChart()) return;
   ObjectsDeleteAll(0,g_prefix+"DYN_");
   DrawTrenderLines(); DrawPivots(); DrawArrows();
   DrawLevel(g_prefix+"DYN_H4_HIGH",g_main.lastHigh,clrOrange,STYLE_SOLID,
             "H4 confirmed swing high",34);
   DrawLevel(g_prefix+"DYN_H4_LOW",g_main.lastLow,clrOrange,STYLE_SOLID,
             "H4 confirmed swing low",34);
   DrawLevel(g_prefix+"DYN_M15_HIGH",g_internal.lastHigh,clrDodgerBlue,STYLE_DASH,
             "M15 confirmed swing high",18);
   DrawLevel(g_prefix+"DYN_M15_LOW",g_internal.lastLow,clrDodgerBlue,STYLE_DASH,
             "M15 confirmed swing low",18);
   DrawPositions(); ChartRedraw(0);
  }
void RenderPanel()
  {
   if(!CanDrawChart()) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double used=ReservedRiskMoney();
   string live=g_liveArrow>0?"BUY":g_liveArrow<0?"SELL":"none";
   string confirmed=g_confirmedArrow>0?"BUY":g_confirmedArrow<0?"SELL":"none";
   string status=InpTradingEnabled?(g_supported?(g_hedging?"ORDERS ON":"BLOCKED: NETTING"):
                                    "BLOCKED: XAUUSD ONLY"):"NEW ENTRIES OFF";
   string panel="FIRST-SIGHT M5 ARROW EA  "+_Symbol+"\n"+
      "Filter "+FilterText()+"\n"+
      "Last closed bands: "+BandStates()+"\n"+
      "Structure: H4 "+DirText(g_main.dir)+
      " | M15 "+DirText(g_internal.dir)+"\n"+
      "M5 arrow: live "+live+" (gray; actionable) / last closed "+confirmed+
      " (green/red)\n"+
      "Blue EMA26 low "+DoubleToString(g_liveEma,_Digits)+
      " | Violet VWAP EMA13 "+DoubleToString(g_liveSmooth,_Digits)+"\n"+
      "Open BUY "+IntegerToString(OwnDirectionCount(DIR_UP))+
      " | SELL "+IntegerToString(OwnDirectionCount(DIR_DOWN))+
      " | No opposite positions allowed\n"+
      "Entry risk "+DoubleToString(InpRiskPct,2)+"% | XAUUSD risk used "+
      DoubleToString(equity>0?100*used/equity:0,2)+" / "+
      DoubleToString(InpMaxCombinedRiskPct,2)+"%\n"+
      "Stop: M5 wick at first sight | Target: "+DoubleToString(InpTargetR,1)+
      "R | Exit: target, stop, or opposite arrow\n"+
      status+" | Decision: "+g_reason;
   Comment(panel);
  }
void AddDealMark(const ulong deal,const bool entry,const int positionDir,
                 const datetime time,const double price,const string why)
  {
   for(int i=0;i<ArraySize(g_eventDeals);i++) if(g_eventDeals[i]==deal) return;
   int count=ArraySize(g_eventDeals);
   ArrayResize(g_eventDeals,count+1); g_eventDeals[count]=deal;
   if(!CanDrawChart()) return;
   if(count>=EVENT_MARK_LIMIT)
     {
      string old=g_prefix+"EVT_"+IntegerToString((long)g_eventDeals[count-EVENT_MARK_LIMIT]);
      ObjectDelete(0,old);
     }
   string id=g_prefix+"EVT_"+IntegerToString((long)deal);
   string label=(positionDir>0?"BUY ":"SELL ")+(entry?"ENTRY":"EXIT");
   DrawLabel(id,time,price,label,entry?clrAqua:clrYellow,
             label+" deal #"+IntegerToString((long)deal)+" "+why);
  }
void AddSignalMark(const datetime candle,const int dir,const double price)
  {
   int count=ArraySize(g_signalMarks);
   ArrayResize(g_signalMarks,count+1); g_signalMarks[count]=candle;
   if(!CanDrawChart()) return;
   if(count>=EVENT_MARK_LIMIT)
      ObjectDelete(0,g_prefix+"SIG_"+
                   IntegerToString((long)g_signalMarks[count-EVENT_MARK_LIMIT]));
   string name=g_prefix+"SIG_"+IntegerToString((long)candle);
   DrawLabel(name,TimeCurrent(),price,"M5 FIRST "+string(dir>0?"BUY":"SELL"),
             clrYellow,"Live M5 arrow first appeared at "+
             TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+
             "; may disappear before candle close");
  }
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0 ||
      !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol ||
      (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;
   bool entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY)==DEAL_ENTRY_IN;
   int dealDir=HistoryDealGetInteger(trans.deal,DEAL_TYPE)==DEAL_TYPE_BUY?DIR_UP:DIR_DOWN;
   int positionDir=entry?dealDir:-dealDir;
   ulong positionId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   int reason=(int)HistoryDealGetInteger(trans.deal,DEAL_REASON);
   string why=entry?"first-sight M5 arrow":
              reason==DEAL_REASON_SL?"stop hit":
              reason==DEAL_REASON_TP?"fixed target hit":ExitIntentFor(positionId);
   datetime when=(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME);
   double price=HistoryDealGetDouble(trans.deal,DEAL_PRICE);
   AddDealMark(trans.deal,entry,positionDir,when,price,why);
   LogEvent(entry?"FILL":"EXIT",
            "deal #"+IntegerToString((long)trans.deal)+" "+why+
            " @ "+DoubleToString(price,_Digits));
   SetReason((entry?"filled ":"closed ")+string(positionDir>0?"BUY":"SELL")+
             " #"+IntegerToString((long)positionId)+": "+why);
   RenderChart(); RenderPanel();
  }

void ReplayAssert(const bool passed,const string rule,int &failed)
  {
   Print("LA5 REPLAY ",passed?"PASS ":"FAIL ",rule);
   if(!passed) failed++;
  }
void RunControlledReplay()
  {
   int failed=0;
   ReplayAssert(ArrowForBar(110,100,99,101)==DIR_UP &&
                ArrowForBar(90,105,99,101)==DIR_DOWN,
                "Trender comparison detects a buy or sell on the first qualifying tick",failed);
   ReplayAssert(ArrowForBar(100,100,99,101)==DIR_NONE,
                "an unqualified live tick has no arrow",failed);
   ReplayAssert(ArrowForBar(102,100,99,101)==DIR_UP &&
                ArrowForBar(100,100,99,101)==DIR_NONE,
                "a first-sight arrow can disappear before candle close",failed);
   datetime start=D'2026.01.01 00:00';
   string why="";
   ReplayAssert(SignalKey(start,DIR_UP)==SignalKey(start,DIR_DOWN) &&
                SignalKey(start,DIR_UP)!=SignalKey(start+300,DIR_UP),
                "only the first live arrow per M5 candle is acted upon",failed);
   double buyTarget=TargetPrice(DIR_UP,100,99);
   double sellTarget=TargetPrice(DIR_DOWN,100,101);
   ReplayAssert(buyTarget>=100+InpTargetR-1e-6 &&
                sellTarget<=100-InpTargetR+1e-6,
                "tick-aligned targets preserve at least the selected R multiple",failed);
   ReplayAssert(AlignmentPasses(ARROW_ONLY,DIR_UP,DIR_DOWN,DIR_DOWN,
                                DIR_DOWN,DIR_DOWN,DIR_DOWN,DIR_DOWN) &&
                AlignmentPasses(ARROW_H4_M15_ALIGNED,DIR_UP,DIR_UP,DIR_UP,
                                DIR_DOWN,DIR_DOWN,DIR_DOWN,DIR_DOWN) &&
               !AlignmentPasses(ARROW_H4_M15_ALIGNED,DIR_UP,DIR_DOWN,DIR_UP,
                                DIR_UP,DIR_UP,DIR_UP,DIR_UP),
                "legacy structure filter uses known H4 and M15 directions",failed);
   ReplayAssert(AlignmentPasses(ARROW_M15_BAND,DIR_UP,0,0,DIR_UP,DIR_DOWN,DIR_DOWN,DIR_DOWN) &&
               !AlignmentPasses(ARROW_M15_BAND,DIR_UP,0,0,DIR_DOWN,DIR_UP,DIR_UP,DIR_UP) &&
                AlignmentPasses(ARROW_M15_H1_BAND,DIR_UP,0,0,DIR_UP,DIR_UP,DIR_DOWN,DIR_DOWN) &&
               !AlignmentPasses(ARROW_M15_H2_BAND,DIR_UP,0,0,DIR_UP,DIR_UP,DIR_DOWN,DIR_UP) &&
                AlignmentPasses(ARROW_M15_H4_BAND,DIR_UP,0,0,DIR_UP,DIR_DOWN,DIR_DOWN,DIR_UP) &&
                AlignmentPasses(ARROW_M15_H1_H2_H4_BAND,DIR_UP,0,0,DIR_UP,DIR_UP,DIR_UP,DIR_UP) &&
               !AlignmentPasses(ARROW_M15_H1_H2_H4_BAND,DIR_UP,0,0,DIR_UP,DIR_UP,DIR_DOWN,DIR_UP),
                "closed M15/H1/H2/H4 band choices test only the selected timeframes",failed);
   ReplayAssert(!CheckSignalPrices(DIR_UP,100,101,why) &&
                !CheckSignalPrices(DIR_DOWN,100,99,why),
                "an invalid exact candle stop is skipped, not moved",failed);
   Print("LA5 REPLAY RESULT: ",failed," failed");
  }

int OnInit()
  {
   if(InpRiskPct<=0 || InpTargetR<=0 || InpMaxCombinedRiskPct<InpRiskPct ||
      InpMaxCombinedRiskPct>100 || InpMaxDeviationPoints<0 || InpMagic==0)
      return INIT_PARAMETERS_INCORRECT;
   g_supported=StringFind(_Symbol,"XAUUSD")==0;
   g_hedging=AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetAsyncMode(false);
   if(MQLInfoInteger(MQL_TESTER)) RunControlledReplay();
   RefreshAnalysis();
   g_lastM5=iTime(_Symbol,PERIOD_M5,0);
   g_lastM15=iTime(_Symbol,PERIOD_M15,0);
   g_lastH4=iTime(_Symbol,PERIOD_H4,0);
   // An already visible arrow at attach/restart is not a new first-sight event.
   if(g_liveArrow!=DIR_NONE && g_lastM5>0)
      MarkSignalHandled(g_lastM5,g_liveArrow);
   SetReason("waiting for first live M5 arrow");
   EventSetTimer(30);
   RenderChart(); RenderPanel();
   LogEvent("START","filter="+FilterText()+" target="+
            DoubleToString(InpTargetR,1)+"R hedging="+IntegerToString((int)g_hedging));
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  {
   EventKillTimer(); ObjectsDeleteAll(0,g_prefix); Comment("");
  }
void OnTimer() { RenderPanel(); }
void OnTick()
  {
   datetime m5=iTime(_Symbol,PERIOD_M5,0);
   datetime m15=iTime(_Symbol,PERIOD_M15,0);
   datetime h4=iTime(_Symbol,PERIOD_H4,0);
   if(m5!=g_lastM5 || m15!=g_lastM15 || h4!=g_lastH4)
     {
      if(g_pending && m5!=g_pendingBar)
        { LogEvent("SKIP","prior reversal signal expired"); g_pending=false; }
      g_lastM5=m5; g_lastM15=m15; g_lastH4=h4;
      if(!RefreshAnalysis()) return;
      SetReason(OwnDirectionCount(DIR_UP)+OwnDirectionCount(DIR_DOWN)>0?
                "holding trades; awaiting target, stop, or opposite M5 arrow":
                "waiting for first live M5 arrow");
      RenderChart(); RenderPanel();
     }
   if(ArraySize(g_m5)<2) return;
   UpdateLiveArrow();
   if(g_pending) ProcessPendingSignal();
   else if(m5>0 && g_liveArrow!=DIR_NONE &&
           !SignalHandled(g_liveBar.time,g_liveArrow))
     {
      g_pending=true; g_pendingBar=g_liveBar.time;
      g_pendingSignal=g_liveBar.time; g_pendingDir=g_liveArrow;
      g_pendingStop=NormalizeDouble(g_liveArrow>0?g_liveBar.low:g_liveBar.high,_Digits);
      MarkSignalHandled(g_pendingSignal,g_pendingDir);
      LogEvent("SIGNAL",string(g_pendingDir>0?"BUY":"SELL")+
               " first seen at "+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+
               " stop="+DoubleToString(g_pendingStop,_Digits)+
               " bands "+BandStates()+
               " H4 structure="+DirText(g_main.dir)+
               " M15 structure="+DirText(g_internal.dir));
      AddSignalMark(g_pendingSignal,g_pendingDir,g_liveBar.close);
      ProcessPendingSignal();
     }
   if(CanDrawChart() && TimeCurrent()-g_lastPanel>=2)
     { g_lastPanel=TimeCurrent(); RenderPanel(); }
  }
