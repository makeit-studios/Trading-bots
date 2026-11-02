// Structure, supply/demand and entry EA. New strategy; older EAs are independent.
#property strict
#property version "1.02"
#include <Trade/Trade.mqh>

input group "Timeframes and structure"
input ENUM_TIMEFRAMES InpMainTF=PERIOD_H4;
input ENUM_TIMEFRAMES InpZoneTF=PERIOD_M15;
input ENUM_TIMEFRAMES InpEntryTF=PERIOD_M5;
input int InpMainPivot=21;
input int InpZonePivot=3;
input int InpEntryPivot=2;
input int InpHistoryBars=900;
input int InpDepartureEvidenceBars=4;

enum EEntryMode { ENTRY_CONFIRMED_ARROW=0,ENTRY_ZONES=1 };
enum EArrowFilter { ARROW_ONLY=0,ARROW_H4_M15_ALIGNED=1 };
input group "Entry model"
input EEntryMode InpEntryMode=ENTRY_CONFIRMED_ARROW;
input ENUM_TIMEFRAMES InpArrowTF=PERIOD_M15;
input EArrowFilter InpArrowFilter=ARROW_ONLY;
input double InpArrowRiskPct=1.0;
input int InpArrowMaxDeviationPoints=20;

input group "Zone evidence (enabled tests add one point each)"
input bool InpUseImbalance=true;
input bool InpUseFVG=true;
input bool InpUseBOS=false;
input bool InpUseSweep=false;
input int InpMinZoneScore=2;
input double InpRevisitFraction=0.60;

input group "Orders and risk"
input bool InpPlaceOrders=true;
input ulong InpMagic=26102145;
input double InpFirstRiskPct=1.0;
input double InpAlignedRetestPct=0.75;
input double InpOtherRetestPct=0.50;
input double InpMaxReservedPct=4.0;
input int InpMaxSpreadPoints=0; // 0 disables this optional check

enum EChartView { CHART_FOCUS=0,CHART_DETAIL=1 };
input group "Context and display"
input EChartView InpChartView=CHART_FOCUS; // Focus shows current decisions; Detail shows historical study marks
input bool InpShowHistory=false; // Broken boxes appear only in Detail when enabled
input int InpMaxDrawnZones=3;
input bool InpShowPivotLabels=true;
input bool InpShowEvidence=true;
input int InpTrenderEMA=26;
input int InpTrenderVWAPEMA=13;
input int InpTrenderLongEMA=200;
input bool InpShowTrenderArrows=true;
input int InpFastSpeedPercent=150;
input int InpSlowSpeedPercent=75;
input bool InpShowNews=true;
input int InpNewsMinutesBefore=30;
input int InpNewsMinutesAfter=15;
input bool InpRunControlledReplay=false; // Tester diagnostic; disabled for normal operation
input long InpVisualCaptureTime1=0; // Tester visual screenshot at server timestamp; 0 disables
input long InpVisualCaptureTime2=0;
input long InpVisualCaptureTime3=0;

enum EDir { DIR_DOWN=-1,DIR_NONE=0,DIR_UP=1 };
enum ERole { ROLE_NONE=0,ROLE_MAIN=1,ROLE_PULLBACK=2,ROLE_INTERNAL=3 };
struct PivotMark { ENUM_TIMEFRAMES tf; datetime time,confirmTime; double price; int type; string tag; };
struct StructureState
  {
   int dir,pending,breakDir;
   datetime breakTime,highTime,lowTime;
   double lastHigh,lastLow,priorHigh,priorLow,breakLevel,liveHigh,liveLow;
   string lastEvent;
  };
struct ZoneRecord
  {
   datetime birth,candidateTime,eligibleTime,firstVisitTime,lastTouch,fvgTime,sweepTime,breakTime;
   int dir,visits,flags,score,originIndex;
   double nearEdge,farEdge,reference,fvgHigh,fvgLow,sweepLevel;
   bool broken,armed,readyRetest,hasFVG;
   string reason;
  };

CTrade g_trade;
MqlRates g_h4[],g_m15[],g_m5[],g_arrowBars[];
PivotMark g_marks[];
ZoneRecord g_zones[];
string g_testerPlaced[];
StructureState g_main,g_internal,g_entry;
datetime g_lastH4=0,g_lastM15=0,g_lastM5=0,g_lastArrowBar=0,g_lastPanel=0;
string g_prefix="SZEA_",g_reason="Starting",g_news="unknown",g_speed="unknown",g_lastSelection="";
int g_chosenSupply=-1,g_chosenDemand=-1;
bool g_hedging=false,g_supported=false;
bool g_captured1=false,g_captured2=false,g_captured3=false;
double g_liveArrow=0,g_confirmedArrow=0,g_trendEMA=0,g_vwapEMA=0,g_longEMA=0;
bool CanDrawChart() { return !MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE); }

string DirText(const int d) { return d>0?"UP":d<0?"DOWN":"UNCLEAR"; }
string TFText(const ENUM_TIMEFRAMES tf)
  { string label=EnumToString(tf); StringReplace(label,"PERIOD_",""); return label; }
string ZoneId(const ZoneRecord &z) { return IntegerToString((long)z.birth)+(z.dir>0?"D":"S"); }
string EvidenceText(const ZoneRecord &z)
  { return "I"+IntegerToString((z.flags&1)!=0)+" F"+IntegerToString((z.flags&2)!=0)+" B"+IntegerToString((z.flags&4)!=0)+" S"+IntegerToString((z.flags&8)!=0); }
double Near(const ZoneRecord &z) { return z.nearEdge; }
double Target(const ZoneRecord &z,const double fraction) { return z.nearEdge+fraction*(z.reference-z.nearEdge); }
double Stop(const ZoneRecord &z) { return z.farEdge; }
bool Touched(const MqlRates &bar,const ZoneRecord &z) { return bar.high>=MathMin(z.nearEdge,z.farEdge) && bar.low<=MathMax(z.nearEdge,z.farEdge); }

void LogEvent(const string kind,const string detail)
  {
   Print("SZEA ",kind," ",detail);
   int f=FileOpen("StructureZoneEntryEA_events.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI,';');
   if(f==INVALID_HANDLE) return;
   FileSeek(f,0,SEEK_END);
   FileWrite(f,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),_Symbol,kind,detail);
   FileClose(f);
  }
void SetReason(const string reason)
  {
   if(g_reason==reason) return;
   g_reason=reason;
   LogEvent("STATE",reason);
  }

int LoadRates(const ENUM_TIMEFRAMES tf,MqlRates &bars[])
  {
   ArrayFree(bars);
   ArraySetAsSeries(bars,false);
   return CopyRates(_Symbol,tf,0,InpHistoryBars,bars);
  }
bool IsPivotHigh(const MqlRates &r[],const int p,const int length)
  {
   for(int j=1;j<=length;j++) if(r[p-j].high>=r[p].high || r[p+j].high>r[p].high) return false;
   return true;
  }
bool IsPivotLow(const MqlRates &r[],const int p,const int length)
  {
   for(int j=1;j<=length;j++) if(r[p-j].low<=r[p].low || r[p+j].low<r[p].low) return false;
   return true;
  }
void AddMark(const ENUM_TIMEFRAMES tf,const datetime tm,const datetime confirmed,const double price,const int type,const string tag)
  {
   int n=ArraySize(g_marks); ArrayResize(g_marks,n+1);
   g_marks[n].tf=tf; g_marks[n].time=tm; g_marks[n].confirmTime=confirmed; g_marks[n].price=price; g_marks[n].type=type; g_marks[n].tag=tag;
  }
void BuildStructure(const MqlRates &r[],const int n,const int length,const ENUM_TIMEFRAMES tf,StructureState &s)
  {
   ZeroMemory(s); s.lastEvent="waiting for swings";
   int highClass=0,lowClass=0,upBreaks=0,downBreaks=0;
   if(n<2*length+5) return;
   for(int i=2*length;i<n-1;i++)
     {
      int p=i-length;
      bool newPivot=false;
      if(IsPivotHigh(r,p,length))
        {
         newPivot=true;
         s.priorHigh=s.lastHigh; s.lastHigh=r[p].high; s.highTime=r[p].time;
         highClass=(s.priorHigh>0 && s.lastHigh>s.priorHigh)?1:(s.priorHigh>0?-1:0);
         AddMark(tf,r[p].time,r[i+1].time,s.lastHigh,1,highClass>0?"HH":highClass<0?"LH":"H");
        }
      if(IsPivotLow(r,p,length))
        {
         newPivot=true;
         s.priorLow=s.lastLow; s.lastLow=r[p].low; s.lowTime=r[p].time;
         lowClass=(s.priorLow>0 && s.lastLow>s.priorLow)?1:(s.priorLow>0?-1:0);
         AddMark(tf,r[p].time,r[i+1].time,s.lastLow,-1,lowClass>0?"HL":lowClass<0?"LL":"L");
        }
      if(newPivot && highClass*lowClass<0) s.dir=DIR_NONE;
      if(s.dir==0 && highClass>0 && lowClass>0 && (s.pending==0 || s.pending==DIR_UP)) { s.dir=DIR_UP; s.pending=DIR_NONE; }
      if(s.dir==0 && highClass<0 && lowClass<0 && (s.pending==0 || s.pending==DIR_DOWN)) { s.dir=DIR_DOWN; s.pending=DIR_NONE; }
      // A break is observable on this closed candle; the pivot label can arrive later.
      if(s.lastHigh>0 && r[i].close>s.lastHigh && r[i-1].close<=s.lastHigh)
        {
         s.breakDir=DIR_UP; s.breakTime=r[i].time; s.breakLevel=s.lastHigh;
         s.lastEvent=(s.dir<0?"bullish CHoCH":"bullish BOS");
         AddMark(tf,r[i].time,r[i+1].time,s.lastHigh,2,s.lastEvent);
         upBreaks++; downBreaks=0;
         if(tf!=InpMainTF || s.dir>=0 || (highClass>0 && lowClass>0 && upBreaks>=2)) { s.dir=DIR_UP; s.pending=DIR_NONE; }
         else { s.pending=DIR_UP; s.dir=DIR_NONE; }
        }
      if(s.lastLow>0 && r[i].close<s.lastLow && r[i-1].close>=s.lastLow)
        {
         s.breakDir=DIR_DOWN; s.breakTime=r[i].time; s.breakLevel=s.lastLow;
         s.lastEvent=(s.dir>0?"bearish CHoCH":"bearish BOS");
         AddMark(tf,r[i].time,r[i+1].time,s.lastLow,-2,s.lastEvent);
         downBreaks++; upBreaks=0;
         if(tf!=InpMainTF || s.dir<=0 || (highClass<0 && lowClass<0 && downBreaks>=2)) { s.dir=DIR_DOWN; s.pending=DIR_NONE; }
         else { s.pending=DIR_DOWN; s.dir=DIR_NONE; }
        }
     }
   int latest=n-1,from=MathMax(0,latest-length);
   s.liveHigh=r[from].high; s.liveLow=r[from].low;
   for(int i=from+1;i<=latest;i++) { s.liveHigh=MathMax(s.liveHigh,r[i].high); s.liveLow=MathMin(s.liveLow,r[i].low); }
  }
double KnownSwing(const MqlRates &r[],const int before,const int length,const int type)
  {
   for(int p=before-length-1;p>=length;p--)
     {
      if(type>0 && IsPivotHigh(r,p,length)) return r[p].high;
      if(type<0 && IsPivotLow(r,p,length)) return r[p].low;
     }
   return 0;
  }
bool SweepAt(const MqlRates &r[],const int i,const int length,const int zoneDir)
  {
   double level=KnownSwing(r,i,length,-zoneDir);
   if(level<=0) return false;
   return zoneDir>0 ? (r[i].low<level && r[i].close>level) : (r[i].high>level && r[i].close<level);
  }
int EnabledScore(const int flags)
  {
   int score=0;
   if(InpUseImbalance && (flags&1)!=0) score++;
   if(InpUseFVG && (flags&2)!=0) score++;
   if(InpUseBOS && (flags&4)!=0) score++;
   if(InpUseSweep && (flags&8)!=0) score++;
   return score;
  }
bool Qualifies(const ZoneRecord &z) { return !z.broken && z.score>=InpMinZoneScore; }

void BuildZones()
  {
   ArrayFree(g_zones);
   int n=ArraySize(g_m15),length=InpZonePivot;
   if(n<80) return;
   for(int b=MathMax(2*length+5,n-InpHistoryBars);b<n-2;b++)
     {
      int d=0;
      double bodyHi=MathMax(g_m15[b].open,g_m15[b].close),bodyLo=MathMin(g_m15[b].open,g_m15[b].close);
      if(g_m15[b+1].close>bodyHi && g_m15[b+1].close>g_m15[b].close) d=DIR_UP;
      else if(g_m15[b+1].close<bodyLo && g_m15[b+1].close<g_m15[b].close) d=DIR_DOWN;
      if(d==0) continue;
      // One base per directional departure leg: an impulse candle is not a new base.
      if(b>0)
        {
         double priorBodyHi=MathMax(g_m15[b-1].open,g_m15[b-1].close);
         double priorBodyLo=MathMin(g_m15[b-1].open,g_m15[b-1].close);
         if(d>0 && g_m15[b].close>priorBodyHi && g_m15[b].close>g_m15[b-1].close) continue;
         if(d<0 && g_m15[b].close<priorBodyLo && g_m15[b].close<g_m15[b-1].close) continue;
        }
      double ref=KnownSwing(g_m15,b,length,d);
      double nearEdge=d>0?g_m15[b].high:g_m15[b].low;
      double farEdge=d>0?g_m15[b].low:g_m15[b].high;
      if(ref<=0 || d*(ref-nearEdge)<=0) continue;
      int zn=ArraySize(g_zones); ArrayResize(g_zones,zn+1);
      ZoneRecord z; ZeroMemory(z);
      z.birth=g_m15[b].time; z.candidateTime=g_m15[b+2].time; z.dir=d; z.originIndex=b; z.nearEdge=nearEdge; z.farEdge=farEdge; z.reference=ref;
      z.reason="candidate";
      bool departed=false;
      int evidenceEnd=MathMin(n-2,b+InpDepartureEvidenceBars);
      for(int k=b+1;k<n-1;k++)
        {
         MqlRates bar=g_m15[k];
         if(d*(bar.close-farEdge)<0) { z.broken=true; z.breakTime=g_m15[k+1].time; z.reason=TFText(InpZoneTF)+" close beyond far edge"; break; }
         if(k<=evidenceEnd && z.visits==0)
           {
            if(d*(bar.close-nearEdge)>0) z.flags|=1;
            if(k>=b+1 && k>=2 && (d>0?bar.low>g_m15[k-2].high:bar.high<g_m15[k-2].low))
              {
               z.flags|=2; z.hasFVG=true;
               z.fvgTime=g_m15[k+1].time;
               z.fvgHigh=d>0?bar.low:g_m15[k-2].low;
               z.fvgLow=d>0?g_m15[k-2].high:bar.high;
              }
            double structural=KnownSwing(g_m15,k,length,d);
            if(structural>0 && d*(bar.close-structural)>0) z.flags|=4;
            if(SweepAt(g_m15,k,length,d))
              { z.flags|=8; z.sweepLevel=KnownSwing(g_m15,k,length,-d); z.sweepTime=g_m15[k+1].time; }
            else if(SweepAt(g_m15,b,length,d))
              { z.flags|=8; z.sweepLevel=KnownSwing(g_m15,b,length,-d); z.sweepTime=z.candidateTime; }
           }
         if(z.eligibleTime==0 && EnabledScore(z.flags)>=InpMinZoneScore) z.eligibleTime=g_m15[k+1].time;
         if(!departed)
           {
            if(d*(bar.close-nearEdge)>0) departed=true;
            continue;
           }
         if(Touched(bar,z))
           {
            if(z.visits==0 || z.readyRetest)
              {
               z.visits++; z.lastTouch=bar.time; z.readyRetest=false;
               if(z.firstVisitTime==0) z.firstVisitTime=bar.time;
              }
           }
         // A later candle can overlap the box and still reach the separation
         // marker with its wick. Only a subsequent touching candle is a retest.
         if(z.visits>0 && k>b+1 && bar.time>z.lastTouch && d*((d>0?bar.high:bar.low)-Target(z,InpRevisitFraction))>=0)
            z.readyRetest=true;
        }
      // The open M15 bar may start a visit. Its close cannot break a zone yet.
      // This lets an M5 close confirm an entry during a fast M15 reversal.
      if(!z.broken && departed && Touched(g_m15[n-1],z) && (z.visits==0 || z.readyRetest))
        { z.visits++; z.lastTouch=g_m15[n-1].time; z.readyRetest=false; if(z.firstVisitTime==0) z.firstVisitTime=g_m15[n-1].time; }
      z.armed=true; z.score=EnabledScore(z.flags);
      if(z.eligibleTime==0 && z.score>=InpMinZoneScore) z.eligibleTime=z.candidateTime;
      if(!z.broken) z.reason=z.score>=InpMinZoneScore?"eligible":"candidate: evidence score low";
      g_zones[zn]=z;
     }
  }

int RoleFor(const int dir)
  {
   if(g_main.dir==dir) return ROLE_MAIN;
   if(g_main.dir==DIR_NONE && g_internal.dir==dir) return ROLE_INTERNAL;
   if(g_main.dir==-dir && g_internal.dir==dir) return ROLE_PULLBACK;
   return ROLE_NONE;
  }
bool InActiveLeg(const ZoneRecord &z)
  {
   if(g_main.dir==DIR_NONE) return true;
   datetime swingStart=g_main.dir==DIR_UP?g_main.lowTime:g_main.highTime;
   if(swingStart==0) return true;
   return z.birth>=swingStart;
  }
int SelectZone(const int dir)
  {
   int best=-1;
   for(int i=0;i<ArraySize(g_zones);i++)
     {
      ZoneRecord z=g_zones[i];
      if(z.dir!=dir || !Qualifies(z) || !z.armed || !InActiveLeg(z)) continue;
      if(best<0) { best=i; continue; }
      ZoneRecord old=g_zones[best];
      // Higher supply and lower demand are the extreme zones of a swing.
      bool moreExtreme=(dir>0?z.farEdge<old.farEdge:z.farEdge>old.farEdge);
      if(moreExtreme || (z.farEdge==old.farEdge && (z.score>old.score || (z.score==old.score && z.birth>old.birth)))) best=i;
     }
   return best;
  }
void ChooseZones() { g_chosenDemand=SelectZone(DIR_UP); g_chosenSupply=SelectZone(DIR_DOWN); }
void LogSelection()
  {
   string demand=g_chosenDemand<0?"none":ZoneId(g_zones[g_chosenDemand])+" V"+IntegerToString(g_zones[g_chosenDemand].visits)+" "+EvidenceText(g_zones[g_chosenDemand]);
   string supply=g_chosenSupply<0?"none":ZoneId(g_zones[g_chosenSupply])+" V"+IntegerToString(g_zones[g_chosenSupply].visits)+" "+EvidenceText(g_zones[g_chosenSupply]);
   string selection="D="+demand+" S="+supply;
   if(selection==g_lastSelection) return;
   g_lastSelection=selection; LogEvent("SELECT",selection);
  }

string TicketKey(const ZoneRecord &z,const int visit,const bool confirmed)
  { return "SZ:"+IntegerToString((long)z.birth)+":"+(z.dir>0?"D":"S")+":"+IntegerToString(visit)+":"+(confirmed?"C":"E"); }
string GlobalKey(const string ticketKey) { return "SZEA_"+IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+IntegerToString((long)InpMagic)+"_"+ticketKey; }
bool WasPlaced(const string key)
  {
   if(MQLInfoInteger(MQL_TESTER))
     { for(int i=0;i<ArraySize(g_testerPlaced);i++) if(g_testerPlaced[i]==key) return true; return false; }
   return GlobalVariableCheck(GlobalKey(key));
  }
void MarkPlaced(const string key)
  {
   if(MQLInfoInteger(MQL_TESTER))
     { int n=ArraySize(g_testerPlaced); ArrayResize(g_testerPlaced,n+1); g_testerPlaced[n]=key; }
   else GlobalVariableSet(GlobalKey(key),(double)TimeCurrent());
  }

double ReservedRiskMoney()
  {
   double total=0,loss=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i); if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      double sl=PositionGetDouble(POSITION_SL),vol=PositionGetDouble(POSITION_VOLUME),open=PositionGetDouble(POSITION_PRICE_OPEN);
      if(sl<=0) return AccountInfoDouble(ACCOUNT_EQUITY)*InpMaxReservedPct/100.0;
      int type=(int)PositionGetInteger(POSITION_TYPE);
      if(!OrderCalcProfit(type==POSITION_TYPE_BUY?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,vol,open,sl,loss)) return AccountInfoDouble(ACCOUNT_EQUITY)*InpMaxReservedPct/100.0;
      total+=MathMax(0,-loss);
     }
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong t=OrderGetTicket(i); if(t==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      double sl=OrderGetDouble(ORDER_SL),vol=OrderGetDouble(ORDER_VOLUME_CURRENT),open=OrderGetDouble(ORDER_PRICE_OPEN);
      if(sl<=0) return AccountInfoDouble(ACCOUNT_EQUITY)*InpMaxReservedPct/100.0;
      int type=(int)OrderGetInteger(ORDER_TYPE);
      bool buy=(type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_BUY_STOP_LIMIT);
      if(!OrderCalcProfit(buy?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,vol,open,sl,loss)) return AccountInfoDouble(ACCOUNT_EQUITY)*InpMaxReservedPct/100.0;
      total+=MathMax(0,-loss);
     }
   return total;
  }
int VolumeDigits(double step)
  { int d=0; while(d<8 && MathAbs(step-MathRound(step))>1e-9) { step*=10; d++; } return d; }
double SizeForRisk(const int dir,const double entry,const double sl,const double riskMoney)
  {
   double oneLotLoss=0;
   if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,1.0,entry,sl,oneLotLoss) || oneLotLoss>=0) return 0;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0 || minLot<=0) return 0;
   double lots=MathFloor((riskMoney/(-oneLotLoss))/step+1e-9)*step;
   double steppedMax=MathFloor(maxLot/step+1e-9)*step;
   lots=NormalizeDouble(MathMin(lots,steppedMax),VolumeDigits(step));
   return lots>=minLot?lots:0;
  }
bool ValidPrices(const int dir,const double entry,const double sl,const double tp,const bool isLimit,string &why)
  {
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) { why="no quote"; return false; }
   if(dir*(entry-sl)<=0 || dir*(tp-entry)<=0) { why="stop/target on wrong side"; return false; }
   double minDist=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(dir*(entry-sl)<minDist || dir*(tp-entry)<minDist) { why="broker stop distance"; return false; }
   if(isLimit && (dir>0?entry>=tick.ask-minDist:entry<=tick.bid+minDist)) { why="limit not pending at current quote"; return false; }
   if(InpMaxSpreadPoints>0 && (tick.ask-tick.bid)/_Point>InpMaxSpreadPoints) { why="spread"; return false; }
   return true;
  }
double ArrowStop(const int dir,const MqlRates &signal)
  {
   return NormalizeDouble(dir>0?signal.low:signal.high,_Digits);
  }
double ArrowTarget(const int dir,const double entry,const datetime signalClose,string &source)
  {
   double best=0;
   source="none";
   for(int i=0;i<ArraySize(g_marks);i++)
     {
      PivotMark p=g_marks[i];
      if(p.confirmTime>signalClose || (p.tf!=InpArrowTF && p.tf!=InpMainTF)) continue;
      if(dir>0?(p.tag!="HH" || p.price<=entry):(p.tag!="LL" || p.price>=entry)) continue;
      if(best==0 || dir*(p.price-entry)<dir*(best-entry))
        { best=p.price; source=TFText(p.tf)+" "+p.tag+" "+TimeToString(p.time,TIME_DATE|TIME_MINUTES); }
     }
   return best>0?NormalizeDouble(best,_Digits):0;
  }
bool ArrowFillPolicy(ENUM_ORDER_TYPE_FILLING &policy)
  {
   int flags=(int)SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((flags&SYMBOL_FILLING_FOK)!=0) { policy=ORDER_FILLING_FOK; return true; }
   if((flags&SYMBOL_FILLING_IOC)!=0) { policy=ORDER_FILLING_IOC; return true; }
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE)!=SYMBOL_TRADE_EXECUTION_MARKET)
      { policy=ORDER_FILLING_RETURN; return true; }
   return false;
  }
bool PlaceArrowTrade()
  {
   int dir=(int)g_confirmedArrow;
   if(dir==DIR_NONE) { SetReason("waiting for a confirmed "+TFText(InpArrowTF)+" arrow"); return false; }
   int n=ArraySize(g_arrowBars);
   if(n<2) return false;
   MqlRates signal=g_arrowBars[n-2];
   string key="AR:"+IntegerToString((long)signal.time)+":"+(dir>0?"B":"S");
   string placedKey=InpPlaceOrders?key:"VIS:"+key;
   if(WasPlaced(placedKey)) return false;
   string why="";
   if(InpArrowFilter==ARROW_H4_M15_ALIGNED && (g_main.dir!=dir || g_internal.dir!=dir))
      { SetReason(key+" skipped: H4/M15 structure not aligned"); return false; }
   if(!g_supported) { SetReason(key+" skipped: XAUUSD symbol required"); return false; }
   if(InpPlaceOrders && !g_hedging) { SetReason(key+" skipped: hedging account required"); return false; }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) { SetReason(key+" skipped: no quote"); return false; }
   double entry=NormalizeDouble(dir>0?tick.ask:tick.bid,_Digits);
   string targetSource="";
   double sl=ArrowStop(dir,signal),tp=ArrowTarget(dir,entry,g_arrowBars[n-1].time,targetSource);
   if(tp<=0) { SetReason(key+" skipped: no confirmed HH/LL ahead of entry"); return false; }
   if(!ValidPrices(dir,entry,sl,tp,false,why)) { SetReason(key+" skipped: "+why); return false; }
   double minDist=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(dir>0?(sl>=tick.bid-minDist || tp<=tick.bid+minDist):(sl<=tick.ask+minDist || tp>=tick.ask-minDist))
      { SetReason(key+" skipped: broker stop distance from closing quote"); return false; }
   double equity=AccountInfoDouble(ACCOUNT_EQUITY),reserved=ReservedRiskMoney();
   double budget=equity*InpArrowRiskPct/100.0;
   double remaining=equity*InpMaxReservedPct/100.0-reserved;
   if(remaining<=0) { SetReason(key+" skipped: reserved risk cap"); return false; }
   budget=MathMin(budget,remaining);
   double worstEntry=entry+dir*InpArrowMaxDeviationPoints*_Point;
   double volume=SizeForRisk(dir,worstEntry,sl,budget);
   if(volume<=0) { SetReason(key+" skipped: minimum lot exceeds risk budget"); return false; }
   double actualLoss=0;
   if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,worstEntry,sl,actualLoss)
      || actualLoss>=0 || -actualLoss>budget+0.01)
      { SetReason(key+" skipped: calculated stop risk"); return false; }
   double margin=0;
   if(!OrderCalcMargin(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,margin)
      || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      { SetReason(key+" skipped: margin"); return false; }
   if(!InpPlaceOrders)
      { MarkPlaced(placedKey); SetReason(key+" confirmed visual "+(dir>0?"BUY":"SELL")+" target "+targetSource); return true; }
   ENUM_ORDER_TYPE_FILLING policy=ORDER_FILLING_FOK;
   if(!ArrowFillPolicy(policy)) { SetReason(key+" skipped: no supported market fill policy"); return false; }
   MqlTradeRequest request={}; MqlTradeCheckResult check={};
   request.action=TRADE_ACTION_DEAL; request.magic=InpMagic; request.symbol=_Symbol;
   request.volume=volume; request.price=entry; request.sl=sl; request.tp=tp;
   request.type=dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   request.deviation=InpArrowMaxDeviationPoints; request.type_filling=policy;
   request.comment=key;
   ResetLastError();
   bool checked=OrderCheck(request,check);
   int checkError=GetLastError();
   if(!checked || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE && check.retcode!=TRADE_RETCODE_PLACED))
      { SetReason(key+" skipped: order check "+IntegerToString((int)check.retcode)+" error="+IntegerToString(checkError)+" "+check.comment); return false; }
   MqlTradeResult result={}; bool sent=OrderSend(request,result);
   if(!sent || (result.retcode!=TRADE_RETCODE_DONE && result.retcode!=TRADE_RETCODE_DONE_PARTIAL && result.retcode!=TRADE_RETCODE_PLACED))
      { SetReason(key+" broker rejected: "+result.comment+" retcode="+IntegerToString((int)result.retcode)); return false; }
   MarkPlaced(placedKey);
   LogEvent("ORDER",key+" market "+(dir>0?"BUY":"SELL")+" quote="+DoubleToString(entry,_Digits)
            +" SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" lots="+DoubleToString(volume,2)
            +" target="+targetSource+" filter="+(InpArrowFilter==ARROW_ONLY?"ARROW_ONLY":"H4_M15_ALIGNED")
            +" H4="+DirText(g_main.dir)+" M15="+DirText(g_internal.dir));
   SetReason(key+" confirmed arrow market order accepted");
   return true;
  }
bool PlaceZoneLimit(const int idx,const int visit,const bool confirmed,const double rawEntry,const int role)
  {
   if(idx<0 || idx>=ArraySize(g_zones) || role==ROLE_NONE) return false;
   ZoneRecord z=g_zones[idx]; string key=TicketKey(z,visit,confirmed),why="";
   string placedKey=InpPlaceOrders?key:"VIS:"+key;
   if(WasPlaced(placedKey)) return false;
   if(!g_supported) { SetReason(key+" skipped: XAUUSD symbol required"); return false; }
   double entry=NormalizeDouble(rawEntry,_Digits),sl=NormalizeDouble(Stop(z),_Digits),tp=NormalizeDouble(Target(z,confirmed?0.90:0.50),_Digits);
   double opposingPrice=0;
   if(role==ROLE_PULLBACK)
     {
      int opposing=z.dir>0?g_chosenSupply:g_chosenDemand;
      if(opposing<0) { SetReason(key+" skipped: no opposing zone for pullback exit"); return false; }
      opposingPrice=g_zones[opposing].nearEdge;
      if(z.dir*(opposingPrice-entry)<=0) { SetReason(key+" skipped: opposing zone behind entry"); return false; }
     }
   if(!ValidPrices(z.dir,entry,sl,tp,true,why)) { SetReason(key+" skipped: "+why); return false; }
   double pct=(visit==1?InpFirstRiskPct:(g_main.dir==z.dir && g_internal.dir==z.dir?InpAlignedRetestPct:InpOtherRetestPct));
   double equity=AccountInfoDouble(ACCOUNT_EQUITY),budget=equity*pct/100.0;
   double reserved=ReservedRiskMoney();
   if(reserved+budget>equity*InpMaxReservedPct/100.0+0.01) { SetReason(key+" skipped: reserved risk cap"); return false; }
   double volume=SizeForRisk(z.dir,entry,sl,budget);
   if(volume<=0) { SetReason(key+" skipped: minimum lot exceeds risk"); return false; }
   double actualLoss=0;
   if(!OrderCalcProfit(z.dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,sl,actualLoss) || actualLoss>=0
      || -actualLoss>budget+0.01 || reserved-actualLoss>equity*InpMaxReservedPct/100.0+0.01)
     { SetReason(key+" skipped: calculated stop risk"); return false; }
   double margin=0;
   if(!OrderCalcMargin(z.dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,volume,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     { SetReason(key+" skipped: margin"); return false; }
   if(!InpPlaceOrders) { SetReason(key+" visual signal"); MarkPlaced(placedKey); return true; }
   if(!g_hedging) { SetReason(key+" skipped: hedging account required"); return false; }
   string comment=key+":"+(role==ROLE_PULLBACK?"P":role==ROLE_MAIN?"M":"I");
   if(role==ROLE_PULLBACK) comment+=":"+IntegerToString((long)MathRound(opposingPrice/_Point));
   MqlTradeRequest request={}; MqlTradeCheckResult check={};
   request.action=TRADE_ACTION_PENDING; request.magic=InpMagic; request.symbol=_Symbol;
   request.volume=volume; request.price=entry; request.sl=sl; request.tp=tp;
   request.type=z.dir>0?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT;
   request.type_time=ORDER_TIME_GTC; request.type_filling=ORDER_FILLING_RETURN; request.comment=comment;
   ResetLastError();
   bool checked=OrderCheck(request,check);
   int checkError=GetLastError();
   // OrderCheck reports a successful validation with retcode 0 ("Done").
   // TRADE_RETCODE_DONE/PLACED are OrderSend result codes.
   if(!checked || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE && check.retcode!=TRADE_RETCODE_PLACED))
     {
      SetReason(key+" skipped: order check retcode="+IntegerToString((int)check.retcode)
                +" error="+IntegerToString(checkError)+" "+check.comment
                +" entry="+DoubleToString(entry,_Digits)+" SL="+DoubleToString(sl,_Digits)
                +" TP="+DoubleToString(tp,_Digits)+" lots="+DoubleToString(volume,2));
      return false;
     }
   MqlTradeResult result={}; bool sent=OrderSend(request,result);
   uint ret=result.retcode;
   if(!sent || (ret!=TRADE_RETCODE_PLACED && ret!=TRADE_RETCODE_DONE) || result.order==0)
     { SetReason(key+" broker rejected: "+result.comment+" retcode="+IntegerToString((int)ret)); return false; }
   MarkPlaced(placedKey);
   LogEvent("ORDER",comment+" entry="+DoubleToString(entry,_Digits)+" SL="+DoubleToString(sl,_Digits)+" TP="+DoubleToString(tp,_Digits)+" lots="+DoubleToString(volume,2));
   SetReason(key+" pending limit placed");
   return true;
  }

bool ConfirmedReady(const ZoneRecord &z)
  {
   if(z.visits<1 || z.lastTouch==0) return false;
   if(g_internal.dir!=z.dir || g_entry.breakDir!=z.dir) return false;
   // Require the break to be the latest closed entry candle, not a stale historical break.
   int n=ArraySize(g_m5); if(n<2 || g_entry.breakTime!=g_m5[n-2].time) return false;
   // Locate the first M5 candle that actually touched during this visit.
   datetime firstTouch=0;
   for(int i=0;i<n-1;i++)
     if(g_m5[i].time>=z.lastTouch && Touched(g_m5[i],z)) { firstTouch=g_m5[i].time; break; }
   return firstTouch>0 && g_entry.breakTime>=firstTouch;
  }
void PlaceEntries()
  {
   SetReason(OrdersTotal()>0?"pending limit working; waiting for next structure":"waiting for zone and M5 structure alignment");
   int choices[2]={g_chosenDemand,g_chosenSupply};
   for(int j=0;j<2;j++)
     {
      int idx=choices[j]; if(idx<0) continue;
      ZoneRecord z=g_zones[idx]; int role=RoleFor(z.dir);
      if(role==ROLE_NONE) continue;
      int nextVisit=z.visits==0?1:(z.readyRetest?z.visits+1:z.visits);
      bool earlyAllowed=(role!=ROLE_MAIN || g_internal.dir==-z.dir);
      if(earlyAllowed && (z.visits==0 || z.readyRetest)) PlaceZoneLimit(idx,nextVisit,false,Near(z),role);
      if(ConfirmedReady(z))
        {
         int n=ArraySize(g_m5); MqlRates bar=g_m5[n-2];
         PlaceZoneLimit(idx,z.visits,true,(bar.high+bar.low)/2.0,role);
        }
     }
  }

int FindZoneByBirth(const datetime birth,const int dir)
  { for(int i=0;i<ArraySize(g_zones);i++) if(g_zones[i].birth==birth && g_zones[i].dir==dir) return i; return -1; }
void MaintainPending()
  {
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i); if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || (ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      string comment=OrderGetString(ORDER_COMMENT),parts[]; int count=StringSplit(comment,':',parts);
      if(count<6 || parts[0]!="SZ") continue;
      datetime birth=(datetime)StringToInteger(parts[1]); int dir=parts[2]=="D"?DIR_UP:DIR_DOWN;
      int zi=FindZoneByBirth(birth,dir);
      string cancelWhy=zi<0?"zone no longer tracked":"";
      if(cancelWhy=="")
        {
         ZoneRecord z=g_zones[zi]; int role=RoleFor(dir);
         if(z.broken) cancelWhy="M15 closed beyond zone far edge";
         else if(!Qualifies(z)) cancelWhy="zone quality no longer qualifies";
         else if(role==ROLE_NONE) cancelWhy="no qualifying structure role";
         else if(parts[5]=="M" && g_main.dir!=dir) cancelWhy="H4 no longer aligned with main entry";
         else if(parts[5]=="P" && g_main.dir!=-dir) cancelWhy="H4 no longer opposite pullback entry";
         else if(parts[5]=="P" && g_internal.dir!=dir) cancelWhy="M15 no longer aligned with pullback entry";
         else if(parts[5]=="I" && g_main.dir!=DIR_NONE && g_main.dir!=dir) cancelWhy="H4 now opposes internal entry";
         if(parts[4]=="C")
           {
            if(cancelWhy=="" && g_entry.breakDir==-dir && g_entry.breakTime+PeriodSeconds(InpEntryTF)>(datetime)OrderGetInteger(ORDER_TIME_SETUP))
               cancelWhy="M5 closed break against confirmed entry";
            double target=OrderGetDouble(ORDER_TP);
            if(cancelWhy=="" && (dir>0?tick.bid>=target:tick.ask<=target)) cancelWhy="target reached before fill";
           }
        }
      if(cancelWhy!="" && InpPlaceOrders)
        {
         bool deleted=g_trade.OrderDelete(ticket);
         if(deleted && g_trade.ResultRetcode()==TRADE_RETCODE_DONE)
           { LogEvent("CANCEL",comment+" "+cancelWhy); SetReason(comment+" canceled: "+cancelWhy); }
         else SetReason(comment+" cancel rejected: "+g_trade.ResultRetcodeDescription());
        }
     }
  }
void CancelZonePendingForArrowModel()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol
         || (ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      string comment=OrderGetString(ORDER_COMMENT);
      if(StringFind(comment,"SZ:")!=0) continue;
      bool deleted=g_trade.OrderDelete(ticket);
      if(deleted && g_trade.ResultRetcode()==TRADE_RETCODE_DONE)
         LogEvent("CANCEL",comment+" zone model disabled");
      else SetReason(comment+" cancel rejected: "+g_trade.ResultRetcodeDescription());
     }
  }
bool OppositeZoneTouched(const int dir,const double bid,const double ask,const double level)
  { return dir>0?bid>=level:ask<=level; }
void ClosePullbacksAtOppositeZone()
  {
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick)) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i); if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      string comment=PositionGetString(POSITION_COMMENT); if(StringFind(comment,":P")<0) continue;
      int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?DIR_UP:DIR_DOWN;
      string parts[]; int count=StringSplit(comment,':',parts); double opposingPrice=0;
      if(count>=7) opposingPrice=(double)StringToInteger(parts[6])*_Point;
      if(opposingPrice<=0)
        {
         int opposite=dir>0?g_chosenSupply:g_chosenDemand; if(opposite<0) continue;
         opposingPrice=g_zones[opposite].nearEdge;
        }
      bool hit=OppositeZoneTouched(dir,tick.bid,tick.ask,opposingPrice);
      if(hit && InpPlaceOrders)
        {
         bool closed=g_trade.PositionClose(ticket);
         if(closed && g_trade.ResultRetcode()==TRADE_RETCODE_DONE) LogEvent("EXIT",comment+" opposing zone touched");
         else SetReason(comment+" close rejected: "+g_trade.ResultRetcodeDescription());
        }
     }
  }

void DrawHLine(const string name,const double price,const color col,const ENUM_LINE_STYLE style=STYLE_DOT)
  {
   if(price<=0) return;
   ObjectCreate(0,name,OBJ_HLINE,0,0,price); ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style); ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
  }
void DrawNamedLevel(const string name,const double price,const color col,const ENUM_LINE_STYLE style,const string meaning,const int bars=20)
  {
   if(price<=0) return;
   if(InpChartView==CHART_FOCUS)
     {
      datetime now=TimeCurrent(),left=now-PeriodSeconds(InpEntryTF)*bars,right=now+PeriodSeconds(InpEntryTF);
      ObjectCreate(0,name,OBJ_TREND,0,left,price,right,price);
      ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
     }
   else DrawHLine(name,price,col,style);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,meaning+" @ "+DoubleToString(price,_Digits));
  }
void MoveNamedLevel(const string name,const double price)
  {
   if(price<=0 || ObjectFind(0,name)<0) return;
   if(InpChartView==CHART_FOCUS)
     {
      datetime left=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
      datetime right=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,1);
      ObjectMove(0,name,0,left,price); ObjectMove(0,name,1,right,price);
     }
   else ObjectSetDouble(0,name,OBJPROP_PRICE,price);
  }
void DrawLabel(const string name,const datetime tm,const double price,const string label,const color col)
  {
   ObjectCreate(0,name,OBJ_TEXT,0,tm,price); ObjectSetString(0,name,OBJPROP_TEXT,label);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col); ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,label);
  }
string ZoneDisplayName(const ZoneRecord &z)
  {
   MqlDateTime dt; TimeToStruct(z.birth,dt);
   return StringFormat("%s %s %02d.%02d %02d:%02d",TFText(InpZoneTF),z.dir>0?"DEMAND":"SUPPLY",dt.mon,dt.day,dt.hour,dt.min);
  }
void DrawZoneRect(const string name,const datetime left,const datetime right,const ZoneRecord &z,const color col,const bool filled,const string tip)
  {
   if(right<=left) return;
   ObjectCreate(0,name,OBJ_RECTANGLE,0,left,z.farEdge,right,z.nearEdge);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col); ObjectSetInteger(0,name,OBJPROP_FILL,filled);
   ObjectSetInteger(0,name,OBJPROP_BACK,true); ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
  }
void RenderChart()
  {
   if(!CanDrawChart()) return;
   ObjectsDeleteAll(0,g_prefix);
   datetime now=TimeCurrent();
   int count=ArraySize(g_zones),shownCount=0;
   bool shown[]; ArrayResize(shown,count);
   for(int i=0;i<count;i++) shown[i]=false;
   if(InpChartView==CHART_FOCUS)
     {
      if(g_chosenDemand>=0 && g_chosenDemand<count) { shown[g_chosenDemand]=true; shownCount++; }
      if(g_chosenSupply>=0 && g_chosenSupply<count && !shown[g_chosenSupply]) { shown[g_chosenSupply]=true; shownCount++; }
      for(int i=count-1;i>=0 && shownCount<InpMaxDrawnZones;i--)
         if(!shown[i] && Qualifies(g_zones[i]) && g_zones[i].armed) { shown[i]=true; shownCount++; }
      int candidates=0;
      for(int i=count-1;i>=0 && shownCount<InpMaxDrawnZones && candidates<1;i--)
         if(!shown[i] && !g_zones[i].broken && !Qualifies(g_zones[i])) { shown[i]=true; shownCount++; candidates++; }
     }
   else
     {
      int start=MathMax(0,count-InpMaxDrawnZones);
      for(int i=start;i<count;i++) if(!g_zones[i].broken || InpShowHistory) shown[i]=true;
     }
   for(int i=0;i<count;i++)
     {
      if(!shown[i]) continue;
      ZoneRecord z=g_zones[i]; if(z.broken && !InpShowHistory) continue;
      string id=g_prefix+"Z"+ZoneId(z);
      color col=z.broken?clrDimGray:(z.score<InpMinZoneScore?clrSlateGray:z.visits>0?(z.dir>0?clrLimeGreen:clrSalmon):(z.dir>0?clrMediumSeaGreen:clrIndianRed));
      datetime right=z.broken?z.breakTime:now+PeriodSeconds(InpZoneTF)*3;
      string eligibleText=z.eligibleTime>0?TimeToString(z.eligibleTime,TIME_DATE|TIME_MINUTES):"not yet";
      string tip=ZoneDisplayName(z)+" | base "+TimeToString(z.birth,TIME_DATE|TIME_MINUTES)+" | candidate "+TimeToString(z.candidateTime,TIME_DATE|TIME_MINUTES)+" | eligible "+eligibleText+" | "+z.reason+" | score="+IntegerToString(z.score)+" visits="+IntegerToString(z.visits)+" | "+EvidenceText(z);
      bool selected=(i==g_chosenDemand || i==g_chosenSupply);
      if(InpChartView==CHART_FOCUS)
        {
         datetime left=z.candidateTime,cutoff=now-PeriodSeconds(InpEntryTF)*96;
         if(left<cutoff) left=cutoff;
         DrawZoneRect(id,left,right,z,col,selected && Qualifies(z),tip);
         string state=z.score<InpMinZoneScore?"CANDIDATE":z.visits>0?"VISITED":"ELIGIBLE";
         string label=(selected?"SELECTED ":"")+ZoneDisplayName(z)+" "+state+" V"+IntegerToString(z.visits)+" Q"+IntegerToString(z.score);
         datetime labelTime=now-PeriodSeconds(InpEntryTF)*45;
         if(labelTime<left) labelTime=left;
         DrawLabel(id+"T",labelTime,z.farEdge,label,col);
         ObjectSetString(0,id+"T",OBJPROP_TOOLTIP,tip);
         if(selected && z.sweepLevel>0 && InpShowEvidence)
            DrawNamedLevel(id+"SWEEP",z.sweepLevel,clrMagenta,STYLE_DOT,ZoneDisplayName(z)+" recorded wick sweep",16);
        }
      else
        {
         if(z.broken || z.score<InpMinZoneScore)
            DrawZoneRect(id,z.candidateTime,right,z,col,false,tip);
         else
           {
            if(z.eligibleTime>z.candidateTime)
               DrawZoneRect(id+"C",z.candidateTime,z.eligibleTime,z,clrSlateGray,false,tip);
            datetime eligibleStart=z.candidateTime>z.eligibleTime?z.candidateTime:z.eligibleTime;
            if(z.firstVisitTime>eligibleStart && z.firstVisitTime<right)
              {
               DrawZoneRect(id+"E",eligibleStart,z.firstVisitTime,z,z.dir>0?clrMediumSeaGreen:clrIndianRed,true,tip);
               DrawZoneRect(id,z.firstVisitTime,right,z,col,true,tip);
              }
            else DrawZoneRect(id,eligibleStart,right,z,col,true,tip);
           }
         string state=z.broken?"BROKEN "+TFText(InpZoneTF)+" close":z.score<InpMinZoneScore?"CANDIDATE":z.visits>0?"VISITED":"ELIGIBLE";
         string flags=StringFormat("%s %s %dpt V%d %s",z.dir>0?"DEMAND":"SUPPLY",state,z.score,z.visits,EvidenceText(z));
         DrawLabel(id+"T",z.candidateTime,z.nearEdge,flags,col);
         if(z.hasFVG && InpShowEvidence)
           {
            string gap=id+"F"; ObjectCreate(0,gap,OBJ_RECTANGLE,0,z.fvgTime,z.fvgHigh,z.broken?z.breakTime:now,z.fvgLow);
            ObjectSetInteger(0,gap,OBJPROP_COLOR,clrDarkSlateBlue); ObjectSetInteger(0,gap,OBJPROP_BACK,true);
           }
         if(z.sweepLevel>0 && InpShowEvidence)
            DrawLabel(id+"SWEEP",z.sweepTime,z.sweepLevel,TFText(InpZoneTF)+" sweep",clrMagenta);
        }
     }
   if(InpShowPivotLabels)
     {
      int mainCount=0,zoneCount=0,entryCount=0;
      int mainLimit=InpChartView==CHART_FOCUS?2:15;
      int zoneLimit=InpChartView==CHART_FOCUS?4:35;
      int entryLimit=InpChartView==CHART_FOCUS?4:40;
      for(int i=ArraySize(g_marks)-1;i>=0;i--)
        {
         PivotMark p=g_marks[i];
         if(InpEntryMode==ENTRY_CONFIRMED_ARROW && p.tf==InpEntryTF) continue;
         if(p.tf==InpMainTF) { if(mainCount++>=mainLimit) continue; }
         else if(p.tf==InpZoneTF) { if(zoneCount++>=zoneLimit) continue; }
         else if(entryCount++>=entryLimit) continue;
         string nm=g_prefix+"P"+IntegerToString((long)p.time)+"_"+IntegerToString((int)p.tf)+"_"+IntegerToString(p.type);
         color tfColor=p.tf==InpMainTF?clrOrange:p.tf==InpZoneTF?clrDodgerBlue:clrGold;
         if(MathAbs(p.type)==2)
           {
            ObjectCreate(0,nm,OBJ_TREND,0,p.confirmTime,p.price,p.confirmTime+PeriodSeconds(p.tf)*3,p.price);
            ObjectSetInteger(0,nm,OBJPROP_COLOR,tfColor);
            ObjectSetInteger(0,nm,OBJPROP_STYLE,STYLE_DASH);
            ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false);
            DrawLabel(nm+"T",p.confirmTime,p.price,TFText(p.tf)+" "+p.tag,tfColor);
            ObjectSetString(0,nm,OBJPROP_TOOLTIP,TFText(p.tf)+" "+p.tag+" | closed break at "+TimeToString(p.confirmTime,TIME_DATE|TIME_MINUTES)+" @ "+DoubleToString(p.price,_Digits));
           }
         else
           {
            DrawLabel(nm,p.time,p.price,TFText(p.tf)+" "+p.tag,tfColor);
            ObjectSetString(0,nm,OBJPROP_TOOLTIP,TFText(p.tf)+" "+p.tag+" | pivot at "+TimeToString(p.time,TIME_DATE|TIME_MINUTES)+"; confirmed at "+TimeToString(p.confirmTime,TIME_DATE|TIME_MINUTES));
           }
        }
     }
   DrawNamedLevel(g_prefix+"H4H",g_main.lastHigh,clrOrange,STYLE_SOLID,"H4 confirmed swing high",48);
   DrawNamedLevel(g_prefix+"H4L",g_main.lastLow,clrOrange,STYLE_SOLID,"H4 confirmed swing low",48);
   DrawNamedLevel(g_prefix+"M15H",g_internal.lastHigh,clrDodgerBlue,STYLE_SOLID,"M15 confirmed swing high",28);
   DrawNamedLevel(g_prefix+"M15L",g_internal.lastLow,clrDodgerBlue,STYLE_SOLID,"M15 confirmed swing low",28);
   if(InpEntryMode==ENTRY_ZONES)
      DrawNamedLevel(g_prefix+"M5BREAK",g_entry.breakLevel,clrGold,STYLE_DASH,"M5 most recent closed structure break",14);
   if(InpChartView==CHART_DETAIL)
     {
      DrawNamedLevel(g_prefix+"H4LIVEH",g_main.liveHigh,clrDarkOrange,STYLE_DOT,"H4 provisional high");
      DrawNamedLevel(g_prefix+"H4LIVEL",g_main.liveLow,clrDarkOrange,STYLE_DOT,"H4 provisional low");
      DrawNamedLevel(g_prefix+"M15LIVEH",g_internal.liveHigh,clrSteelBlue,STYLE_DOT,"M15 provisional high");
      DrawNamedLevel(g_prefix+"M15LIVEL",g_internal.liveLow,clrSteelBlue,STYLE_DOT,"M15 provisional low");
      DrawNamedLevel(g_prefix+"M15BREAK",g_internal.breakLevel,clrDeepSkyBlue,STYLE_DASH,"M15 most recent closed structure break");
      if(InpEntryMode==ENTRY_ZONES)
        {
         DrawNamedLevel(g_prefix+"M5H",g_entry.lastHigh,clrGold,STYLE_SOLID,"M5 confirmed swing high");
         DrawNamedLevel(g_prefix+"M5L",g_entry.lastLow,clrGold,STYLE_SOLID,"M5 confirmed swing low");
        }
      if(g_main.breakTime>0) DrawLabel(g_prefix+"H4EVENT",g_main.breakTime+PeriodSeconds(InpMainTF),g_main.breakLevel,"H4 "+g_main.lastEvent,clrOrange);
      if(g_internal.breakTime>0) DrawLabel(g_prefix+"M15EVENT",g_internal.breakTime+PeriodSeconds(InpZoneTF),g_internal.breakLevel,"M15 "+g_internal.lastEvent,clrDodgerBlue);
      if(InpEntryMode==ENTRY_ZONES && g_entry.breakTime>0) DrawLabel(g_prefix+"M5EVENT",g_entry.breakTime+PeriodSeconds(InpEntryTF),g_entry.breakLevel,"M5 "+g_entry.lastEvent,clrGold);
     }
   if(InpEntryMode==ENTRY_ZONES)
     {
      DrawNamedLevel(g_prefix+"M5LIVEH",g_entry.liveHigh,clrKhaki,STYLE_DOT,"M5 provisional high (live)",14);
      DrawNamedLevel(g_prefix+"M5LIVEL",g_entry.liveLow,clrKhaki,STYLE_DOT,"M5 provisional low (live)",14);
     }
   int selected[2]={g_chosenDemand,g_chosenSupply};
   for(int j=0;j<2;j++) if(selected[j]>=0)
     {
      ZoneRecord z=g_zones[selected[j]]; string side=j==0?"D":"S";
      DrawNamedLevel(g_prefix+side+"FROZEN",z.reference,clrWhite,STYLE_DASH,ZoneDisplayName(z)+" opposing swing frozen at birth",20);
      DrawNamedLevel(g_prefix+side+"60",Target(z,InpRevisitFraction),clrYellow,STYLE_DOT,ZoneDisplayName(z)+" 60% departure needed before another visit",20);
      if(InpChartView==CHART_DETAIL)
        {
         DrawNamedLevel(g_prefix+side+"NEAR",z.nearEdge,clrAqua,STYLE_SOLID,ZoneDisplayName(z)+" near edge");
         DrawNamedLevel(g_prefix+side+"SWEEP",z.sweepLevel,clrMagenta,STYLE_DOT,ZoneDisplayName(z)+" sweep level");
         DrawNamedLevel(g_prefix+side+"50",Target(z,0.50),clrGreen,STYLE_DOT,ZoneDisplayName(z)+" early 50% target");
         DrawNamedLevel(g_prefix+side+"90",Target(z,0.90),clrLime,STYLE_DOT,ZoneDisplayName(z)+" confirmed 90% target");
         DrawNamedLevel(g_prefix+side+"SL",Stop(z),clrRed,STYLE_DOT,ZoneDisplayName(z)+" far edge / stop");
        }
     }
   ChartRedraw(0);
  }

void RenderOrderLevels()
  {
   if(!CanDrawChart()) return;
   ObjectsDeleteAll(0,g_prefix+"ORDER_");
   for(int i=0;i<OrdersTotal();i++)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || (ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      string id=g_prefix+"ORDER_"+IntegerToString((long)ticket);
      double entry=OrderGetDouble(ORDER_PRICE_OPEN),sl=OrderGetDouble(ORDER_SL),tp=OrderGetDouble(ORDER_TP);
      string comment=OrderGetString(ORDER_COMMENT),parts[]; int partCount=StringSplit(comment,':',parts);
      string label=comment;
      if(partCount>=6)
        {
         string side=parts[2]=="D"?"BUY":"SELL",kind=parts[4]=="E"?"EARLY":"M5 MIDPOINT";
         label=side+" "+kind+" V"+parts[3]+" "+(parts[5]=="P"?"PULLBACK":parts[5]=="M"?"MAIN":"INTERNAL");
        }
      DrawNamedLevel(id+"_ENTRY",entry,clrAqua,STYLE_SOLID,label+" pending entry",9);
      string stopName=g_prefix+"ORDER_SL_"+DoubleToString(sl,_Digits);
      string targetName=g_prefix+"ORDER_TP_"+DoubleToString(tp,_Digits);
      if(ObjectFind(0,stopName)<0) DrawNamedLevel(stopName,sl,clrRed,STYLE_DASH,"Pending order stop",9);
      if(ObjectFind(0,targetName)<0) DrawNamedLevel(targetName,tp,clrLime,STYLE_DASH,"Pending order target",9);
      datetime labelTime=TimeCurrent()-PeriodSeconds(InpEntryTF)*(10+i*5);
      DrawLabel(id+"_NAME",labelTime,entry,label+" @ "+DoubleToString(entry,_Digits),clrAqua);
      ObjectSetString(0,id+"_NAME",OBJPROP_TOOLTIP,comment+" | entry "+DoubleToString(entry,_Digits)+" SL "+DoubleToString(sl,_Digits)+" TP "+DoubleToString(tp,_Digits));
     }
   if(InpEntryMode==ENTRY_CONFIRMED_ARROW)
     {
      for(int i=0;i<PositionsTotal();i++)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol
            || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
         string comment=PositionGetString(POSITION_COMMENT);
         if(StringFind(comment,"AR:")!=0) continue;
         string id=g_prefix+"ORDER_POS_"+IntegerToString((long)ticket);
         string side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"BUY":"SELL";
         double entry=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
         DrawNamedLevel(id+"_ENTRY",entry,clrAqua,STYLE_SOLID,side+" confirmed arrow fill",9);
         DrawNamedLevel(id+"_SL",sl,clrRed,STYLE_DASH,side+" arrow initial stop",9);
         DrawNamedLevel(id+"_TP",tp,clrLime,STYLE_DASH,side+" arrow fixed target",9);
         datetime labelTime=TimeCurrent()-PeriodSeconds(InpArrowTF)*(10+i*5);
         DrawLabel(id+"_NAME",labelTime,entry,side+" ARROW @ "+DoubleToString(entry,_Digits),clrAqua);
         ObjectSetString(0,id+"_NAME",OBJPROP_TOOLTIP,comment+" | fill "+DoubleToString(entry,_Digits)+" SL "+DoubleToString(sl,_Digits)+" TP "+DoubleToString(tp,_Digits));
        }
     }
  }
void UpdateLiveLevels()
  {
   double h=iHigh(_Symbol,InpMainTF,0),l=iLow(_Symbol,InpMainTF,0);
   if(h>0) g_main.liveHigh=MathMax(g_main.liveHigh,h);
   if(l>0) g_main.liveLow=g_main.liveLow>0?MathMin(g_main.liveLow,l):l;
   h=iHigh(_Symbol,InpZoneTF,0); l=iLow(_Symbol,InpZoneTF,0);
   if(h>0) g_internal.liveHigh=MathMax(g_internal.liveHigh,h);
   if(l>0) g_internal.liveLow=g_internal.liveLow>0?MathMin(g_internal.liveLow,l):l;
   h=iHigh(_Symbol,InpEntryTF,0); l=iLow(_Symbol,InpEntryTF,0);
   if(h>0) g_entry.liveHigh=MathMax(g_entry.liveHigh,h);
   if(l>0) g_entry.liveLow=g_entry.liveLow>0?MathMin(g_entry.liveLow,l):l;
   if(!CanDrawChart()) return;
   MoveNamedLevel(g_prefix+"H4LIVEH",g_main.liveHigh);
   MoveNamedLevel(g_prefix+"H4LIVEL",g_main.liveLow);
   MoveNamedLevel(g_prefix+"M15LIVEH",g_internal.liveHigh);
   MoveNamedLevel(g_prefix+"M15LIVEL",g_internal.liveLow);
   MoveNamedLevel(g_prefix+"M5LIVEH",g_entry.liveHigh);
   MoveNamedLevel(g_prefix+"M5LIVEL",g_entry.liveLow);
  }

void ComputeTrender(const MqlRates &r[],const int n)
  {
   g_liveArrow=0; g_confirmedArrow=0;
   if(n<InpTrenderLongEMA+3) return;
   double alpha=2.0/(InpTrenderEMA+1.0),vAlpha=2.0/(InpTrenderVWAPEMA+1.0),longAlpha=2.0/(InpTrenderLongEMA+1.0);
   double emaLow=r[0].low,emaLong=r[0].close,smoothed=0,prevSmooth=0;
   double sumPV=0,sumVol=0; int priorDay=-1;
   for(int i=0;i<n;i++)
     {
      MqlDateTime dt; TimeToStruct(r[i].time,dt); int day=dt.year*10000+dt.mon*100+dt.day;
      if(day!=priorDay) { sumPV=0; sumVol=0; priorDay=day; }
      double vol=MathMax(1,(double)r[i].tick_volume),typical=(r[i].high+r[i].low+r[i].close)/3.0;
      sumPV+=typical*vol; sumVol+=vol; double vwap=sumPV/sumVol;
      emaLow=i==0?r[i].low:alpha*r[i].low+(1-alpha)*emaLow;
      emaLong=i==0?r[i].close:longAlpha*r[i].close+(1-longAlpha)*emaLong;
      prevSmooth=smoothed; smoothed=i==0?vwap:vAlpha*vwap+(1-vAlpha)*smoothed;
      if(i>=n-120 && i>0)
        {
         // Pine's close[1] is compared with the current bar's mvwap value.
         int arrow=(r[i].close>emaLow && r[i-1].close<smoothed && r[i].close>smoothed)?1:
                   (r[i].close<emaLow && r[i-1].close>smoothed && r[i].close<smoothed)?-1:0;
         if(i==n-2) g_confirmedArrow=arrow; else { g_liveArrow=arrow; g_trendEMA=emaLow; g_vwapEMA=smoothed; g_longEMA=emaLong; }
         if(CanDrawChart() && InpShowTrenderArrows && i<n-1 && arrow!=0
            && (InpChartView==CHART_DETAIL || i>=n-24))
           {
            string fixed=g_prefix+"ARROW_"+IntegerToString((long)r[i].time);
            if(ObjectFind(0,fixed)<0)
              {
               ObjectCreate(0,fixed,arrow>0?OBJ_ARROW_UP:OBJ_ARROW_DOWN,0,r[i].time,arrow>0?r[i].low:r[i].high);
               ObjectSetInteger(0,fixed,OBJPROP_COLOR,arrow>0?clrLime:clrRed);
               ObjectSetString(0,fixed,OBJPROP_TOOLTIP,"Simple Trender confirmed at candle close");
              }
           }
        }
     }
   if(CanDrawChart() && InpShowTrenderArrows)
     {
      string live=g_prefix+"ARROW_LIVE"; ObjectDelete(0,live);
      if(g_liveArrow!=0)
        {
         ObjectCreate(0,live,g_liveArrow>0?OBJ_ARROW_UP:OBJ_ARROW_DOWN,0,r[n-1].time,g_liveArrow>0?r[n-1].low:r[n-1].high);
         ObjectSetInteger(0,live,OBJPROP_COLOR,clrGray); ObjectSetString(0,live,OBJPROP_TOOLTIP,"Simple Trender provisional; may disappear");
        }
     }
  }
void UpdateSpeed()
  {
   int n=ArraySize(g_m15); if(n<120) return;
   double recent=0,baseline[]; ArrayResize(baseline,100);
   for(int i=0;i<100;i++) baseline[i]=g_m15[n-102+i].high-g_m15[n-102+i].low;
   ArraySort(baseline); double median=(baseline[49]+baseline[50])/2.0;
   for(int i=n-15;i<n-1;i++) recent+=g_m15[i].high-g_m15[i].low;
   recent/=14.0;
   if(median<=0) return;
   double ratio=100*recent/median;
   g_speed=DoubleToString(ratio,0)+"% of median "+(ratio>=InpFastSpeedPercent?"FAST":ratio<=InpSlowSpeedPercent?"SLOW":"NORMAL");
  }
void UpdateNews()
  {
   if(!InpShowNews) { g_news="off"; return; }
   if(MQLInfoInteger(MQL_TESTER)) { g_news="unknown in tester"; return; }
   datetime now=TimeTradeServer(); MqlCalendarValue values[];
   int count=CalendarValueHistory(values,now-InpNewsMinutesAfter*60,now+InpNewsMinutesBefore*60,NULL,"USD");
   if(count<0) { g_news="unavailable"; return; }
   g_news="none in window";
   for(int i=0;i<count;i++)
     {
      MqlCalendarEvent event;
      if(CalendarEventById(values[i].event_id,event) && event.importance==CALENDAR_IMPORTANCE_HIGH)
        { g_news="HIGH USD "+event.name+" "+TimeToString(values[i].time,TIME_MINUTES); break; }
     }
  }
void RenderPanel()
  {
   if(!CanDrawChart()) return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY),reserved=ReservedRiskMoney();
   int pending=0; for(int i=0;i<OrdersTotal();i++) if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagic) pending++;
   if(InpEntryMode==ENTRY_CONFIRMED_ARROW)
     {
      string lastArrow=g_confirmedArrow>0?"BUY":g_confirmedArrow<0?"SELL":"none";
      string panel="CONFIRMED ARROW ENTRY  "+_Symbol+"\n"+
         TFText(InpMainTF)+" "+DirText(g_main.dir)+" | "+TFText(InpZoneTF)+" "+DirText(g_internal.dir)+" | filter "+(InpArrowFilter==ARROW_ONLY?"ARROW ONLY":"H4 + M15 ALIGNED")+"\n"+
         "Speed "+g_speed+" | USD news "+g_news+" | zones OFF\n"+
         "Simple Trender: live "+(g_liveArrow>0?"BUY":g_liveArrow<0?"SELL":"none")+" / last closed "+lastArrow+" | gray=provisional green/red=closed\n"+
         "Entry: market on confirmed "+TFText(InpArrowTF)+" arrow | SL=signal candle wick | TP=nearest confirmed HH/LL ahead\n"+
         "Risk "+DoubleToString(InpArrowRiskPct,2)+"% per arrow | reserved "+DoubleToString(equity>0?100*reserved/equity:0,2)+" / "+DoubleToString(InpMaxReservedPct,2)+"% | pending "+IntegerToString(pending)+"\n"+
         (InpPlaceOrders?(g_supported?(g_hedging?"ORDERS ON":"ORDERS BLOCKED: NETTING"):"ORDERS BLOCKED: SYMBOL"):"VISUAL MODE")+" | Decision: "+g_reason;
      Comment(panel); return;
     }
   string zoneD=g_chosenDemand<0?"none":ZoneDisplayName(g_zones[g_chosenDemand])+" V"+IntegerToString(g_zones[g_chosenDemand].visits)+" Q"+IntegerToString(g_zones[g_chosenDemand].score)+" "+EvidenceText(g_zones[g_chosenDemand])+" "+DoubleToString(g_zones[g_chosenDemand].farEdge,_Digits)+".."+DoubleToString(g_zones[g_chosenDemand].nearEdge,_Digits);
   string zoneS=g_chosenSupply<0?"none":ZoneDisplayName(g_zones[g_chosenSupply])+" V"+IntegerToString(g_zones[g_chosenSupply].visits)+" Q"+IntegerToString(g_zones[g_chosenSupply].score)+" "+EvidenceText(g_zones[g_chosenSupply])+" "+DoubleToString(g_zones[g_chosenSupply].nearEdge,_Digits)+".."+DoubleToString(g_zones[g_chosenSupply].farEdge,_Digits);
   string panel="STRUCTURE / ZONES / ENTRY  "+_Symbol+"\n"+
      TFText(InpMainTF)+" "+DirText(g_main.dir)+(g_main.pending!=0?" pending "+DirText(g_main.pending):"")+" | "+TFText(InpZoneTF)+" "+DirText(g_internal.dir)+" | "+TFText(InpEntryTF)+" "+DirText(g_entry.dir)+" "+g_entry.lastEvent+"\n"+
      TFText(InpMainTF)+" live high/low "+DoubleToString(g_main.liveHigh,_Digits)+" / "+DoubleToString(g_main.liveLow,_Digits)+" | speed "+g_speed+" | news "+g_news+"\n"+
      "Demand "+zoneD+"\n"+
      "Supply "+zoneS+"\n"+
      "Quality I/F/B/S "+IntegerToString((int)InpUseImbalance)+"/"+IntegerToString((int)InpUseFVG)+"/"+IntegerToString((int)InpUseBOS)+"/"+IntegerToString((int)InpUseSweep)+" min "+IntegerToString(InpMinZoneScore)+"\n"+
      "Chart "+(InpChartView==CHART_FOCUS?"FOCUS":"DETAIL")+": red supply, green demand; orange H4, blue M15, gold M5; aqua entry, red stop, lime target. Hover for names.\n"+
      "Trender EMA(low) "+DoubleToString(g_trendEMA,_Digits)+" vwapEMA "+DoubleToString(g_vwapEMA,_Digits)+" EMA200 "+DoubleToString(g_longEMA,_Digits)+" arrows live/closed "+DoubleToString(g_liveArrow,0)+"/"+DoubleToString(g_confirmedArrow,0)+"\n"+
      "Risk reserved "+DoubleToString(equity>0?100*reserved/equity:0,2)+" / "+DoubleToString(InpMaxReservedPct,2)+"% | Pending "+IntegerToString(pending)+" | "+(InpPlaceOrders?(g_supported?(g_hedging?"ORDERS ON":"ORDERS BLOCKED: NETTING"):"ORDERS BLOCKED: SYMBOL"):"VISUAL MODE")+"\n"+
      "Decision: "+g_reason;
   Comment(panel);
  }
void CaptureVisualReplay(const long captureTime,bool &captured)
  {
   if(captured || captureTime<=0 || !MQLInfoInteger(MQL_TESTER) || !MQLInfoInteger(MQL_VISUAL_MODE)
      || (long)TimeCurrent()<captureTime) return;
   captured=true;
   ChartRedraw(0);
   string stamp=TimeToString((datetime)captureTime,TIME_DATE|TIME_MINUTES);
   StringReplace(stamp,".",""); StringReplace(stamp," ","_"); StringReplace(stamp,":","");
   string file="SZEA_visual_"+stamp+".png";
   ResetLastError();
   bool saved=ChartScreenShot(0,file,1440,900,ALIGN_RIGHT);
   Print("SZEA CAPTURE ",file," saved=",saved," error=",GetLastError());
  }

bool RefreshAll()
  {
   int h=LoadRates(InpMainTF,g_h4),z=LoadRates(InpZoneTF,g_m15),e=LoadRates(InpEntryTF,g_m5);
   int a=InpEntryMode==ENTRY_CONFIRMED_ARROW?LoadRates(InpArrowTF,g_arrowBars):e;
   if((InpEntryMode==ENTRY_CONFIRMED_ARROW && a<InpTrenderLongEMA+3)
      || (InpEntryMode==ENTRY_ZONES && (h<2*InpMainPivot+10 || z<120 || e<MathMax(2*InpEntryPivot+10,InpTrenderLongEMA+3))))
      { SetReason("waiting for required timeframe history"); return false; }
   ArrayFree(g_marks);
   BuildStructure(g_h4,h,InpMainPivot,InpMainTF,g_main);
   BuildStructure(g_m15,z,InpZonePivot,InpZoneTF,g_internal);
   BuildStructure(g_m5,e,InpEntryPivot,InpEntryTF,g_entry);
   if(InpEntryMode==ENTRY_ZONES) { BuildZones(); ChooseZones(); LogSelection(); }
   else { ArrayFree(g_zones); g_chosenDemand=-1; g_chosenSupply=-1; }
   UpdateSpeed();
   RenderChart();
   if(InpEntryMode==ENTRY_CONFIRMED_ARROW) ComputeTrender(g_arrowBars,a);
   else ComputeTrender(g_m5,e);
   RenderPanel();
   return true;
  }
void ReplayAssert(const bool passed,const string rule,int &failed)
  {
   Print("SZEA REPLAY ",passed?"PASS ":"FAIL ",rule);
   if(!passed) failed++;
  }
void RunControlledReplay()
  {
   int failed=0;
   MqlRates r[]; ArrayResize(r,80);
   datetime start=D'2026.01.01 00:00';
   for(int i=0;i<80;i++)
     { r[i].time=start+i*900; r[i].open=100; r[i].high=101; r[i].low=99; r[i].close=100; }
   r[10].high=110;
   r[40].high=111; r[40].close=109;
   StructureState s;
   BuildStructure(r,43,3,InpEntryTF,s);
   ReplayAssert(s.breakDir!=DIR_UP,"wick above known high, close inside is no BOS",failed);
   ReplayAssert(SweepAt(r,40,3,DIR_DOWN),"wick sweep closes back inside",failed);
   r[41].high=112; r[41].close=111;
   BuildStructure(r,43,3,InpEntryTF,s);
   ReplayAssert(s.breakDir==DIR_UP && s.breakTime==r[41].time,"closed break is observed on break candle",failed);
   ArrayFree(g_marks);
   for(int i=0;i<80;i++)
     { r[i].open=100; r[i].high=101; r[i].low=99; r[i].close=100; }
   r[30].high=106;
   r[50].open=100; r[50].close=99; r[50].high=101; r[50].low=97;
   r[51].open=100; r[51].close=104; r[51].high=105; r[51].low=100;
   r[52].open=103; r[52].close=106; r[52].high=107; r[52].low=102;
   r[53].open=104; r[53].close=104; r[53].high=106; r[53].low=102;
   r[54].open=103; r[54].close=103; r[54].high=104; r[54].low=100;
   r[55].open=102; r[55].close=102; r[55].high=103; r[55].low=96;
   r[56].open=104; r[56].close=104; r[56].high=105; r[56].low=100;
   for(int i=57;i<80;i++) { r[i].open=104; r[i].close=104; r[i].high=105; r[i].low=104; }
   ArrayResize(g_m15,80); for(int i=0;i<80;i++) g_m15[i]=r[i];
   BuildZones(); int zi=FindZoneByBirth(r[50].time,DIR_UP);
   ReplayAssert(zi>=0 && g_zones[zi].visits==1 && g_zones[zi].readyRetest,"same-encounter taps count once; overlapping later wick can arm retest",failed);
   ReplayAssert(zi>=0 && !g_zones[zi].broken,"wick through demand far edge closes inside and preserves zone",failed);
   r[57].open=102; r[57].close=102; r[57].high=103; r[57].low=100;
   r[58].open=100; r[58].close=96; r[58].high=100; r[58].low=95;
   for(int i=0;i<80;i++) g_m15[i]=r[i];
   BuildZones(); zi=FindZoneByBirth(r[50].time,DIR_UP);
   ReplayAssert(zi>=0,"base candle creates a demand zone",failed);
   if(zi>=0)
     {
      ZoneRecord z=g_zones[zi];
      ReplayAssert(z.nearEdge==101 && z.farEdge==97 && z.reference==106,"original full wick and prior opposing swing frozen",failed);
      ReplayAssert((z.flags&3)==3 && z.score==EnabledScore(z.flags),"imbalance and three-candle FVG recorded",failed);
      ReplayAssert((z.flags&2)!=0 && z.visits==2,"filled FVG point survives later visits",failed);
      ReplayAssert(z.candidateTime==r[52].time && z.eligibleTime==r[53].time,"candidate and eligibility wait for their candles to close",failed);
      ReplayAssert(z.visits==2,"two taps stay one visit; 60 percent departure permits retest",failed);
      ReplayAssert(z.broken && z.breakTime==r[59].time && z.reason==TFText(InpZoneTF)+" close beyond far edge","only closed far-edge break invalidates",failed);
      ReplayAssert(Target(z,0.50)==103.5 && Target(z,0.90)==105.5 && Stop(z)==97,"exact early and confirmed target and stop math",failed);
      ReplayAssert((104.0+100.0)/2.0==102.0 && Target(z,0.90)>102.0,"M5 full high-low midpoint stays below its 90 percent target",failed);
     }
   // Mirror the demand sequence to cover the later supply break in zones 1/2.
   MqlRates mirrored[]; ArrayResize(mirrored,80);
   for(int i=0;i<80;i++)
     {
      mirrored[i]=r[i];
      mirrored[i].open=300-r[i].open; mirrored[i].close=300-r[i].close;
      mirrored[i].high=300-r[i].low; mirrored[i].low=300-r[i].high;
      g_m15[i]=mirrored[i];
     }
   BuildZones(); int si=FindZoneByBirth(r[50].time,DIR_DOWN);
   ReplayAssert(si>=0 && g_zones[si].nearEdge==199 && g_zones[si].farEdge==203
                && g_zones[si].broken && g_zones[si].visits==2,
                "supply retest closes beyond far edge and retires lower box",failed);
   ZoneRecord upper; ZeroMemory(upper);
   upper.birth=r[60].time; upper.dir=DIR_DOWN; upper.nearEdge=209;
   upper.farEdge=214; upper.reference=194; upper.flags=3;
   upper.score=EnabledScore(upper.flags); upper.armed=true;
   int upperIndex=ArraySize(g_zones); ArrayResize(g_zones,upperIndex+1); g_zones[upperIndex]=upper;
   g_main.dir=DIR_NONE;
   ReplayAssert(SelectZone(DIR_DOWN)==upperIndex,
                "after lower supply breaks the qualifying upper supply is selected",failed);
   MqlRates m5[]; ArrayResize(m5,22);
   for(int i=0;i<22;i++)
     { m5[i].time=start+i*300; m5[i].open=100; m5[i].high=101; m5[i].low=99; m5[i].close=100; }
   m5[10].high=110;
   m5[18].high=105; m5[18].low=100;
   m5[20].open=109; m5[20].high=113; m5[20].low=109; m5[20].close=111;
   ArrayResize(g_m5,22); for(int i=0;i<22;i++) g_m5[i]=m5[i];
   BuildStructure(g_m5,22,2,InpEntryTF,g_entry);
   ZoneRecord entryZone; ZeroMemory(entryZone);
   entryZone.dir=DIR_UP; entryZone.nearEdge=101; entryZone.farEdge=97;
   entryZone.reference=120; entryZone.visits=1; entryZone.lastTouch=m5[18].time;
   g_internal.dir=DIR_UP;
   ReplayAssert(ConfirmedReady(entryZone) && (m5[20].high+m5[20].low)/2.0==111
                && Target(entryZone,0.90)>111,
                "zone touch then closed M5 BOS permits midpoint limit",failed);
   g_entry.breakTime=m5[19].time;
   ReplayAssert(!ConfirmedReady(entryZone),"stale M5 break cannot confirm a new entry",failed);
   g_main.dir=DIR_DOWN; g_internal.dir=DIR_UP;
   ReplayAssert(RoleFor(DIR_UP)==ROLE_PULLBACK && RoleFor(DIR_DOWN)==ROLE_MAIN,"H4 down, M15 up permits internal buy and main sell",failed);
   ReplayAssert(!OppositeZoneTouched(DIR_UP,208,208.2,209)
                && OppositeZoneTouched(DIR_UP,209,209.2,209),
                "pullback buy exits when bid reaches opposing supply",failed);
   g_internal.dir=DIR_DOWN;
   ReplayAssert(RoleFor(DIR_UP)==ROLE_NONE && RoleFor(DIR_DOWN)==ROLE_MAIN,"M15 realignment ends new pullback buys",failed);
   ArrayFree(g_marks);
   datetime closeAt=start+100000;
   AddMark(InpZoneTF,start+1000,closeAt-900,106,1,"HH");
   AddMark(InpZoneTF,start+2000,closeAt+900,104,1,"HH");
   AddMark(InpZoneTF,start+3000,closeAt-900,92,-1,"LL");
   string targetSource="";
   ReplayAssert(ArrowStop(DIR_UP,r[50])==r[50].low && ArrowStop(DIR_DOWN,r[50])==r[50].high,
                "arrow stop is the signal candle's exact far wick",failed);
   ReplayAssert(ArrowTarget(DIR_UP,101,closeAt,targetSource)==106 && StringFind(targetSource,"HH")>=0,
                "arrow buy targets only an already confirmed HH above entry",failed);
   ReplayAssert(ArrowTarget(DIR_DOWN,101,closeAt,targetSource)==92 && StringFind(targetSource,"LL")>=0,
                "arrow sell targets an already confirmed LL below entry",failed);
   ReplayAssert(ArrowTarget(DIR_UP,107,closeAt,targetSource)==0,
                "arrow signal without a known HH ahead has no invented target",failed);
   MqlRates arrowFixture[]; int fixtureCount=MathMax(205,InpTrenderLongEMA+5);
   ArrayResize(arrowFixture,fixtureCount);
   for(int i=0;i<fixtureCount;i++)
     {
      arrowFixture[i].time=start+i*900; arrowFixture[i].open=101;
      arrowFixture[i].high=102; arrowFixture[i].low=99;
      arrowFixture[i].close=101; arrowFixture[i].tick_volume=1;
     }
   arrowFixture[fixtureCount-3].close=100;
   arrowFixture[fixtureCount-2].close=110;
   arrowFixture[fixtureCount-2].high=111;
   ComputeTrender(arrowFixture,fixtureCount);
   ReplayAssert(g_confirmedArrow==DIR_UP,"M15 Trender arrow is confirmed on the closed candle",failed);
   ArrayFree(g_m15); ArrayFree(g_m5); ArrayFree(g_zones);
   ArrayFree(g_marks);
   ZeroMemory(g_main); ZeroMemory(g_internal); ZeroMemory(g_entry);
   Print("SZEA REPLAY RESULT: ",failed," failed");
  }
int OnInit()
  {
   if((InpEntryMode==ENTRY_ZONES && (PeriodSeconds(InpMainTF)<=PeriodSeconds(InpZoneTF) || PeriodSeconds(InpZoneTF)<=PeriodSeconds(InpEntryTF)))
      || (InpEntryMode==ENTRY_CONFIRMED_ARROW && (PeriodSeconds(InpMainTF)<=PeriodSeconds(InpArrowTF) || InpArrowTF!=InpZoneTF))
      || InpMainPivot<2 || InpZonePivot<2 || InpEntryPivot<2 || InpHistoryBars<MathMax(300,InpTrenderLongEMA+3)
      || InpTrenderEMA<1 || InpTrenderVWAPEMA<1 || InpTrenderLongEMA<1
      || InpArrowRiskPct<=0 || InpArrowMaxDeviationPoints<0 || InpMaxReservedPct<InpArrowRiskPct
      || (InpEntryMode==ENTRY_ZONES && (InpDepartureEvidenceBars<1 || InpMinZoneScore<0 || InpMinZoneScore>4
      || InpMaxDrawnZones<1 || InpRevisitFraction<=0 || InpRevisitFraction>1 || InpFirstRiskPct<=0
      || InpAlignedRetestPct<=0 || InpOtherRetestPct<=0 || InpMaxReservedPct<InpFirstRiskPct)))
      return INIT_PARAMETERS_INCORRECT;
   g_supported=StringFind(_Symbol,"XAUUSD")==0;
   if(!g_supported) Print("SZEA: XAUUSD orders blocked; attached to ",_Symbol);
   g_hedging=AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   g_trade.SetExpertMagicNumber(InpMagic); g_trade.SetTypeFillingBySymbol(_Symbol);
   if(InpRunControlledReplay) RunControlledReplay();
   EventSetTimer(60); RefreshAll(); UpdateNews();
   if(InpEntryMode==ENTRY_CONFIRMED_ARROW)
     {
      CancelZonePendingForArrowModel();
      g_lastH4=iTime(_Symbol,InpMainTF,0);
      g_lastM15=iTime(_Symbol,InpZoneTF,0);
      g_lastM5=iTime(_Symbol,InpEntryTF,0);
      g_lastArrowBar=iTime(_Symbol,InpArrowTF,0);
      SetReason("waiting for next closed "+TFText(InpArrowTF)+" arrow");
     }
   RenderOrderLevels(); RenderPanel();
   LogEvent("START","mode="+(InpEntryMode==ENTRY_CONFIRMED_ARROW?"ARROW":"ZONES")+" hedging="+IntegerToString((int)g_hedging));
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason) { EventKillTimer(); ObjectsDeleteAll(0,g_prefix); Comment(""); }
void OnTimer() { UpdateNews(); RenderPanel(); }
void OnTick()
  {
   datetime h=iTime(_Symbol,InpMainTF,0),z=iTime(_Symbol,InpZoneTF,0),e=iTime(_Symbol,InpEntryTF,0);
   datetime a=InpEntryMode==ENTRY_CONFIRMED_ARROW?iTime(_Symbol,InpArrowTF,0):e;
   bool newArrowBar=(a!=g_lastArrowBar);
   if(h!=g_lastH4 || z!=g_lastM15 || e!=g_lastM5 || newArrowBar)
     {
      g_lastH4=h; g_lastM15=z; g_lastM5=e;
      g_lastArrowBar=a;
      if(RefreshAll())
        {
         if(InpEntryMode==ENTRY_ZONES) { MaintainPending(); PlaceEntries(); }
         else if(newArrowBar) PlaceArrowTrade();
         RenderOrderLevels(); RenderPanel();
        }
     }
   else if(CanDrawChart())
     {
      // Current bar is provisional; its arrow never acts as an entry trigger.
      if(InpEntryMode==ENTRY_CONFIRMED_ARROW)
        { int n=LoadRates(InpArrowTF,g_arrowBars); if(n>InpTrenderLongEMA+3) ComputeTrender(g_arrowBars,n); }
      else
        { int n=LoadRates(InpEntryTF,g_m5); if(n>InpTrenderLongEMA+3) ComputeTrender(g_m5,n); }
     }
   ClosePullbacksAtOppositeZone();
   if(CanDrawChart()) UpdateLiveLevels();
   if(TimeCurrent()-g_lastPanel>=5) { g_lastPanel=TimeCurrent(); RenderPanel(); }
   CaptureVisualReplay(InpVisualCaptureTime1,g_captured1);
   CaptureVisualReplay(InpVisualCaptureTime2,g_captured2);
   CaptureVisualReplay(InpVisualCaptureTime3,g_captured3);
  }
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0 || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol || (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=InpMagic) return;
   string kind=HistoryDealGetInteger(trans.deal,DEAL_ENTRY)==DEAL_ENTRY_IN?"FILL":"EXIT";
   string detail=HistoryDealGetString(trans.deal,DEAL_COMMENT)+" deal="+IntegerToString((long)trans.deal);
   LogEvent(kind,detail); SetReason(kind+" "+detail);
   RenderOrderLevels(); RenderPanel();
  }
