// Closed-arrow Simple Trender research: separate direction, stop, and exit variants.
// Tester-only; every position has a broker-side protective stop.
#property strict
#property version "1.000"

enum ETrend { TREND_H1=1, TREND_H4=4 };
enum EEntry { ENTRY_SWING_CONTROL=0, ENTRY_M15_BAND=1, ENTRY_M1_M5_M15=2,
              ENTRY_M1_M5_ONLY=3 };
enum EExit { EXIT_FIXED_R=0, EXIT_RUNNER=1, EXIT_BAND_RUNNER=2 };
enum EStopBand { STOP_SIGNAL_BAND=0, STOP_M3_BAND=3, STOP_M5_BAND=5 };
enum ESignalTrigger { SIGNAL_VWAP_CROSS=0, SIGNAL_EMA_RECLAIM=1 };
enum EBandState
  {
   BAND_UNKNOWN=0,
   BAND_EXPANDING=1,
   BAND_MATURE=2,
   BAND_CONTRACTING=3,
   BAND_COMPRESSED=4,
   BAND_REEXPANDING=5
  };
input group "Frozen research rules"
input EEntry InpEntry=ENTRY_M15_BAND;
input EStopBand InpStopBand=STOP_SIGNAL_BAND;
input ETrend InpTrend=TREND_H1;
input EExit InpExit=EXIT_BAND_RUNNER;
input ENUM_TIMEFRAMES InpM5OnlySignalTf=PERIOD_M1;
input ESignalTrigger InpSignalTrigger=SIGNAL_VWAP_CROSS;
input int InpBandEmaPeriod=26;
input int InpVwapSmoothPeriod=13;
input int InpMajorEmaPeriod=200;
input int InpTrendSlopeBars=3;
input int InpScreenHistoryBars=0;
input string InpRunId="runner_research";
input ulong InpMagic=26102800;
input double InpSymbolRiskPct=0.5;
input double InpFixedTargetR=1.5;
input bool InpStageEnabled=false;
input bool InpIndependentFixed=true;
input int InpRunnerManagement=0; // 0 baseline, 1 breakeven, 2 breakeven plus ATR trail

#define PIVOT_SIDE 2
#define M5_COUNT 2500
#define M1_COUNT 6000
#define STRUCTURE_COUNT 500
#define ATR_LENGTH 14
#define WIDTH_LOOKBACK 24
#define STAGE_PROBE_FRACTION 0.25
#define STAGE_CONFIRM_R 0.5
#define STAGE_WINDOW_SECONDS 600

struct BandContext
  {
   bool ready;
   datetime time;
   int dir,state;
   double close,previousClose;
   double emaLow,smoothVwap,ema200,previousEMA200;
   double atr,widthATR,widthThree,median,q25;
   double emaSlope,vwapSlope,widthChange;
  };

struct PositionTrace
  {
   long id;
   int dir;
   int leg;
   double entry,stop,target,volume,best,riskUSD;
   datetime entryTime;
   string exitRule;
  };
PositionTrace g_trace[];
datetime g_lastM1=0,g_lastM3=0,g_lastM5=0,g_lastM15=0,g_lastSignalM15=0;
string g_file="";
int g_signals=0;
datetime g_previousBandTime=0;
double g_previousBandA=0,g_previousBandB=0,g_lastBandA=0,g_lastBandB=0;
double g_previousEMA200=0;
int g_panelM15=0,g_panelH1=0,g_panelH4=0,g_panelM15State=BAND_UNKNOWN;
int g_panelM5=0,g_panelM5State=BAND_UNKNOWN;
string g_panelM15Shape="waiting",g_panelH1Shape="waiting",g_panelH4Shape="waiting";
double g_panelM15Width=0,g_panelM15Median=0,g_panelM15Q25=0;
double g_lastStopBandA=0,g_lastStopBandB=0;
datetime g_lastStopBandTime=0;
bool g_runnerWarning=false;
string g_warningReason="none";
int g_bandSide=0;
string g_panelArrow="none";
string g_lastDecision="waiting for a closed M5 arrow";
string g_bandObjects[];
datetime g_stageLastM1=0,g_stageStarted=0,g_stageSignal=0;
int g_atrHandle=INVALID_HANDLE,g_snapshotMonth=0;
long g_manageId=0;
bool g_beTriggered=false,g_trailTriggered=false;
datetime g_manageBar=0,g_lastManageAttempt=0,g_lastInvalidLog=0;
double g_trailCandidate=0;


bool Visual() { return MQLInfoInteger(MQL_VISUAL_MODE)!=0; }
string DirectionText(const int dir)
  { return dir>0?"UP":dir<0?"DOWN":"not confirmed"; }
string BandStateText(const int state)
  {
   if(state==BAND_EXPANDING) return "EXPANDING";
   if(state==BAND_MATURE) return "MATURE";
   if(state==BAND_CONTRACTING) return "CONTRACTING";
   if(state==BAND_COMPRESSED) return "COMPRESSED";
   if(state==BAND_REEXPANDING) return "RE-EXPANDING";
   return "UNKNOWN";
  }
string EntryText()
  {
   if(InpEntry==ENTRY_M1_M5_ONLY) return EnumToString(InpM5OnlySignalTf)+" / M5";
   if(InpEntry==ENTRY_M1_M5_M15) return "M1 / M5+M15";
   if(InpEntry==ENTRY_M15_BAND) return "M15 BAND";
   return "SWING CONTROL";
  }
string StopText()
  {
   if(InpStopBand==STOP_M3_BAND) return "M3";
   if(InpStopBand==STOP_M5_BAND) return "M5";
   if(InpEntry==ENTRY_M1_M5_ONLY) return EnumToString(InpM5OnlySignalTf);
   return InpEntry==ENTRY_M1_M5_M15?"M1":"M5";
  }
string ExitText()
  {
   string target=DoubleToString(InpFixedTargetR,2)+"R";
   if(InpExit==EXIT_FIXED_R) return "single "+target;
   if(InpStageEnabled) return "staged runner + confirmed "+target;
   if(InpExit==EXIT_BAND_RUNNER) return "band runner + repeat "+target;
   return "structure runner + repeat "+target;
  }
string ShapeText(const double high,const double priorHigh,
                 const double low,const double priorLow)
  {
   if(priorHigh<=0 || priorLow<=0) return "waiting";
   string highs=high>priorHigh?"HH":high<priorHigh?"LH":"equal H";
   string lows=low>priorLow?"HL":low<priorLow?"LL":"equal L";
   return highs+"/"+lows;
  }
void Panel()
  {
   if(!Visual()) return;
   ulong core=0,sat=0,base=0;
   bool hasCore=OwnLeg(1,core),hasSat=OwnLeg(2,sat),hasBase=OwnLeg(3,base);
   Comment("Simple Trender research  |  ",_Symbol,"  |  ",EntryText()," / ",ExitText(),"\n",
           "M5: ",DirectionText(g_panelM5),"  ",BandStateText(g_panelM5State),
           "   M15 info: ",DirectionText(g_panelM15),"  ",BandStateText(g_panelM15State),
           "  width/median/q25: ",Num(g_panelM15Width,3),"/",Num(g_panelM15Median,3),"/",Num(g_panelM15Q25,3),"\n",
           "H1 info: ",DirectionText(g_panelH1)," (",g_panelH1Shape,")",
           "   H4 info: ",DirectionText(g_panelH4)," (",g_panelH4Shape,")",
           "   closed ",(InpEntry==ENTRY_M1_M5_ONLY?EnumToString(InpM5OnlySignalTf):
                          (InpEntry==ENTRY_M1_M5_M15?"M1":"M5"))," arrow: ",g_panelArrow,"\n",
           "Frozen band  |  EMA-low: ",Num(g_lastBandA,_Digits),
           "   smoothed VWAP: ",Num(g_lastBandB,_Digits),"\n",
           "Stop band: ",StopText()," closed ",TimeToString(g_lastStopBandTime,TIME_DATE|TIME_MINUTES),
           "  outer EMA/VWAP: ",Num(g_lastStopBandA,_Digits),"/",Num(g_lastStopBandB,_Digits),
           "  warning: ",
           g_runnerWarning?("ON "+g_warningReason):"off","\n",
           "Runner: ",hasCore?"OPEN":"flat","   1R leg: ",hasSat?"OPEN":"flat",
           "   baseline: ",hasBase?"OPEN":"flat","\n",
           "Latest decision: ",StringSubstr(g_lastDecision,0,150));
  }
void Level(const string name,const double price,const color shade)
  {
   if(!Visual() || price<=0) return;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,shade);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
  }
void Mark(const string name,const datetime when,const double price,
          const int arrowCode,const color shade,const string tip)
  {
   if(!Visual()) return;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_ARROW,0,when,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,arrowCode);
   ObjectSetInteger(0,name,OBJPROP_COLOR,shade);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
  }
void BandSegment(const datetime when,const double a,const double b,
                 const double ema200,const int dir)
  {
   if(!Visual() || when<=0) return;
   g_lastBandA=a; g_lastBandB=b;
   if(g_previousBandTime>0 && g_previousBandTime<when)
     {
      string key=IntegerToString((long)when);
      string one="TRR_BAND_A_"+key,two="TRR_BAND_B_"+key;
      string three="TRR_EMA200_"+key;
      ObjectCreate(0,one,OBJ_TREND,0,g_previousBandTime,g_previousBandA,when,a);
      ObjectCreate(0,two,OBJ_TREND,0,g_previousBandTime,g_previousBandB,when,b);
      ObjectCreate(0,three,OBJ_TREND,0,g_previousBandTime,g_previousEMA200,when,ema200);
      ObjectSetInteger(0,one,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,two,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,three,OBJPROP_RAY_RIGHT,false);
      ObjectSetInteger(0,one,OBJPROP_COLOR,dir<0?clrTomato:clrLimeGreen);
      ObjectSetInteger(0,two,OBJPROP_COLOR,dir<0?clrOrangeRed:clrGreen);
      ObjectSetInteger(0,three,OBJPROP_COLOR,clrDodgerBlue);
      ObjectSetInteger(0,one,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,two,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,three,OBJPROP_WIDTH,1);
      int size=ArraySize(g_bandObjects);
      ArrayResize(g_bandObjects,size+3);
      g_bandObjects[size]=one; g_bandObjects[size+1]=two; g_bandObjects[size+2]=three;
      if(ArraySize(g_bandObjects)>144)
        {
         for(int k=0;k<3;k++) ObjectDelete(0,g_bandObjects[k]);
         for(int k=3;k<ArraySize(g_bandObjects);k++) g_bandObjects[k-3]=g_bandObjects[k];
         ArrayResize(g_bandObjects,ArraySize(g_bandObjects)-3);
        }
     }
   g_previousBandTime=when; g_previousBandA=a; g_previousBandB=b;
   g_previousEMA200=ema200;
   Panel();
  }

string Num(const double x,const int digits=6) { return DoubleToString(x,digits); }
double GridUp(const double x,const double tick)
  { return NormalizeDouble(MathCeil(x/tick-1e-7)*tick,_Digits); }
double GridDown(const double x,const double tick)
  { return NormalizeDouble(MathFloor(x/tick+1e-7)*tick,_Digits); }
int DayKey(const datetime t)
  { MqlDateTime d; TimeToStruct(t,d); return d.year*10000+d.mon*100+d.day; }
void Log(const string kind,const string detail)
  {
   g_lastDecision=kind+" "+detail;
   Print("TRR ",kind," ",InpRunId," ",_Symbol," ",detail);
   int h=FileOpen(g_file,FILE_READ|FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI,';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),kind,detail);
   FileClose(h);
   Panel();
  }
int Rates(const ENUM_TIMEFRAMES tf,const int wanted,MqlRates &r[])
  { ArrayFree(r); ArraySetAsSeries(r,false); return CopyRates(_Symbol,tf,0,wanted,r); }
int HistoryCount(const ENUM_TIMEFRAMES tf)
  {
   int wanted=tf==PERIOD_M1?M1_COUNT:(tf==PERIOD_M5?M5_COUNT:1200);
   if(InpScreenHistoryBars>0) wanted=MathMin(wanted,InpScreenHistoryBars);
   return wanted;
  }
int BandDirectionAt(const MqlRates &r[],const double &ema[],const double &vwap[],const int p)
  {
   if(p<InpTrendSlopeBars) return 0;
   if(r[p].close>ema[p] && r[p].close>vwap[p] &&
      ema[p]>ema[p-InpTrendSlopeBars] && vwap[p]>vwap[p-InpTrendSlopeBars]) return 1;
   if(r[p].close<ema[p] && r[p].close<vwap[p] &&
      ema[p]<ema[p-InpTrendSlopeBars] && vwap[p]<vwap[p-InpTrendSlopeBars]) return -1;
   return 0;
  }
double Quantile(const double &sorted[],const double fraction)
  {
   int n=ArraySize(sorted);
   if(n<=0) return 0;
   double at=(n-1)*fraction;
   int low=(int)MathFloor(at),high=(int)MathCeil(at);
   if(high<=low) return sorted[low];
   return sorted[low]+(sorted[high]-sorted[low])*(at-low);
  }
bool BuildBandContext(const ENUM_TIMEFRAMES tf,BandContext &out)
  {
   ZeroMemory(out);
   MqlRates r[];
   int n=Rates(tf,HistoryCount(tf),r);
   int last=n-2;
   if(n<MathMax(InpMajorEmaPeriod+60,WIDTH_LOOKBACK+InpTrendSlopeBars+8)) return false;
   double ema[],smooth[],ema200[],atr[],width[];
   ArrayResize(ema,n); ArrayResize(smooth,n); ArrayResize(ema200,n);
   ArrayResize(atr,n); ArrayResize(width,n);
   double alpha=2.0/(InpBandEmaPeriod+1.0),beta=2.0/(InpVwapSmoothPeriod+1.0),gamma=2.0/(InpMajorEmaPeriod+1.0);
   double pv=0,vol=0; int day=0;
   for(int i=0;i<=last;i++)
     {
      ema[i]=(i==0?r[i].low:alpha*r[i].low+(1-alpha)*ema[i-1]);
      ema200[i]=(i==0?r[i].close:gamma*r[i].close+(1-gamma)*ema200[i-1]);
      int key=DayKey(r[i].time);
      if(key!=day) { day=key; pv=0; vol=0; }
      double v=MathMax(1.0,(double)r[i].tick_volume);
      pv+=((r[i].high+r[i].low+r[i].close)/3.0)*v; vol+=v;
      double rawVwap=pv/vol;
      smooth[i]=(i==0?rawVwap:beta*rawVwap+(1-beta)*smooth[i-1]);
      double tr=r[i].high-r[i].low;
      if(i>0) tr=MathMax(tr,MathMax(MathAbs(r[i].high-r[i-1].close),MathAbs(r[i].low-r[i-1].close)));
      atr[i]=(i==0?tr:(atr[i-1]*(ATR_LENGTH-1)+tr)/ATR_LENGTH);
      width[i]=atr[i]>0?MathAbs(ema[i]-smooth[i])/atr[i]:0;
     }
   double sample[]; ArrayResize(sample,WIDTH_LOOKBACK);
   for(int k=0;k<WIDTH_LOOKBACK;k++) sample[k]=width[last-WIDTH_LOOKBACK+k];
   ArraySort(sample);
   out.ready=true; out.time=r[last].time; out.close=r[last].close;
   out.previousClose=r[last-1].close; out.emaLow=ema[last]; out.smoothVwap=smooth[last];
   out.ema200=ema200[last]; out.previousEMA200=ema200[last-1]; out.atr=atr[last];
   out.widthATR=width[last]; out.widthThree=width[last-3];
   out.median=Quantile(sample,0.5); out.q25=Quantile(sample,0.25);
   out.emaSlope=ema[last]-ema[last-3]; out.vwapSlope=smooth[last]-smooth[last-3];
   out.widthChange=width[last]-width[last-3];
   out.dir=BandDirectionAt(r,ema,smooth,last);
   int previousDir=BandDirectionAt(r,ema,smooth,last-3);
   bool rising=out.widthChange>0;
   if(out.widthATR<=out.q25) out.state=BAND_COMPRESSED;
   else if(rising && out.widthATR>=out.median) out.state=BAND_EXPANDING;
   else if(!rising && out.widthATR>=out.median) out.state=BAND_MATURE;
   else if(!rising && out.widthATR>out.q25) out.state=BAND_CONTRACTING;
   else if(rising && out.widthATR<out.median && out.dir!=0 && out.dir==previousDir)
      out.state=BAND_REEXPANDING;
   else out.state=BAND_UNKNOWN;
   return true;
  }
string BandFields(const string prefix,const BandContext &b)
  {
   return prefix+"Dir="+IntegerToString(b.dir)+
          " "+prefix+"State="+IntegerToString(b.state)+
          " "+prefix+"Width="+Num(b.widthATR,6)+
          " "+prefix+"Median="+Num(b.median,6)+
          " "+prefix+"Q25="+Num(b.q25,6)+
          " "+prefix+"Width3="+Num(b.widthThree,6)+
          " "+prefix+"WidthChange="+Num(b.widthChange,6)+
          " "+prefix+"EmaSlope="+Num(b.emaSlope,8)+
          " "+prefix+"VwapSlope="+Num(b.vwapSlope,8)+
          " "+prefix+"Close="+Num(b.close,_Digits)+
          " "+prefix+"EmaLow="+Num(b.emaLow,_Digits)+
          " "+prefix+"Vwap="+Num(b.smoothVwap,_Digits)+
          " "+prefix+"Ema200="+Num(b.ema200,_Digits);
  }
bool PivotHigh(const MqlRates &r[],const int p)
  {
   for(int j=1;j<=PIVOT_SIDE;j++)
      if(r[p-j].high>=r[p].high || r[p+j].high>r[p].high) return false;
   return true;
  }
bool PivotLow(const MqlRates &r[],const int p)
  {
   for(int j=1;j<=PIVOT_SIDE;j++)
      if(r[p-j].low<=r[p].low || r[p+j].low<r[p].low) return false;
   return true;
  }
// last is the newest bar allowed in this decision. The pivot needs two later closed bars.
bool StructureDetail(const ENUM_TIMEFRAMES tf,const int last,int &dir,
                     double &latestHigh,double &latestLow,
                     double &oldHigh,double &oldLow)
  {
   dir=0; latestHigh=0; latestLow=0; oldHigh=0; oldLow=0;
   MqlRates r[];
   int n=Rates(tf,STRUCTURE_COUNT,r);
   int end=(last<0?n-2:last);
   if(n<20 || end>=n || end<2*PIVOT_SIDE+2) return false;
   for(int p=PIVOT_SIDE;p<=end-PIVOT_SIDE;p++)
     {
      if(PivotHigh(r,p)) { oldHigh=latestHigh; latestHigh=r[p].high; }
      if(PivotLow(r,p))  { oldLow=latestLow; latestLow=r[p].low; }
     }
   if(oldHigh<=0 || oldLow<=0) return false;
   if(latestHigh>oldHigh && latestLow>oldLow) dir=1;
   if(latestHigh<oldHigh && latestLow<oldLow) dir=-1;
   return true;
  }
bool Structure(const ENUM_TIMEFRAMES tf,const int last,int &dir,
               double &latestHigh,double &latestLow)
  {
   double oldHigh=0,oldLow=0;
   return StructureDetail(tf,last,dir,latestHigh,latestLow,oldHigh,oldLow);
  }
bool ArrowAt(const ENUM_TIMEFRAMES tf,int &dir,double &outer,double &bandA,double &bandB,
           double &ema200,datetime &barTime)
  {
   dir=0; outer=0; bandA=0; bandB=0; ema200=0; barTime=0;
   MqlRates r[];
   int n=Rates(tf,HistoryCount(tf),r);
   if(n<InpBandEmaPeriod+5) return false;
   int last=n-2;
   double alpha=2.0/(InpBandEmaPeriod+1.0);
   double beta=2.0/(InpVwapSmoothPeriod+1.0);
   double gamma=2.0/(InpMajorEmaPeriod+1.0);
   double ema=0,smooth=0,pv=0,vol=0;
   int day=0;
   for(int i=0;i<=last;i++)
     {
      ema=(i==0?r[i].low:alpha*r[i].low+(1-alpha)*ema);
      ema200=(i==0?r[i].close:gamma*r[i].close+(1-gamma)*ema200);
      int key=DayKey(r[i].time);
      if(key!=day) { day=key; pv=0; vol=0; }
      double v=MathMax(1.0,(double)r[i].tick_volume);
      pv+=((r[i].high+r[i].low+r[i].close)/3.0)*v;
      vol+=v;
      double vwap=pv/vol;
      smooth=(i==0?vwap:beta*vwap+(1-beta)*smooth);
     }
   double c=r[last].close,previous=r[last-1].close;
   g_bandSide=c>ema?1:c<ema?-1:0;
   if(InpSignalTrigger==SIGNAL_VWAP_CROSS)
     {
      if(c>ema && previous<smooth && c>smooth) dir=1;
      if(c<ema && previous>smooth && c<smooth) dir=-1;
     }
   else if(InpSignalTrigger==SIGNAL_EMA_RECLAIM)
     {
      if(r[last].low<=ema && c>ema && c>smooth && c>r[last].open) dir=1;
      if(r[last].high>=ema && c<ema && c<smooth && c<r[last].open) dir=-1;
     }
   bandA=ema; bandB=smooth;
   barTime=r[last].time;
   if(dir==0) return false;
   outer=(dir>0?MathMin(ema,smooth):MathMax(ema,smooth));
   return true;
  }
int LegMagic(const int leg) { return (int)InpMagic+leg; }
bool OwnLeg(const int leg,ulong &ticket)
  {
   ticket=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong t=PositionGetTicket(i);
      if(t>0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
         PositionGetInteger(POSITION_MAGIC)==LegMagic(leg)) { ticket=t; return true; }
     }
   return false;
  }
int TraceIndex(const long id)
  { for(int i=0;i<ArraySize(g_trace);i++) if(g_trace[i].id==id) return i; return -1; }
double OpenStopRisk()
  {
   double risk=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long magic=PositionGetInteger(POSITION_MAGIC);
      if(magic<LegMagic(1) || magic>LegMagic(3)) continue;
      double stop=PositionGetDouble(POSITION_SL),loss=0;
      if(stop<=0) return DBL_MAX;
      ENUM_ORDER_TYPE type=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?
                           ORDER_TYPE_BUY:ORDER_TYPE_SELL;
      if(!OrderCalcProfit(type,_Symbol,PositionGetDouble(POSITION_VOLUME),
                          PositionGetDouble(POSITION_PRICE_OPEN),stop,loss)) return DBL_MAX;
      risk+=MathMax(0,-loss);
     }
   return risk;
  }
double RiskVolume(const int dir,const double entry,const double stop,const double budget)
  {
   double loss=0;
   if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,1.0,
                       entry,stop,loss) || loss>=0) return 0;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0 || minLot<=0 || maxLot<=0) return 0;
   double lots=MathFloor(budget/(-loss)/step+1e-9)*step;
   lots=MathMin(lots,MathFloor(maxLot/step+1e-9)*step);
   lots=NormalizeDouble(lots,8);
   return lots>=minLot?lots:0;
  }
bool Filling(ENUM_ORDER_TYPE_FILLING &policy)
  {
   int flags=(int)SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((flags&SYMBOL_FILLING_FOK)!=0) { policy=ORDER_FILLING_FOK; return true; }
   if((flags&SYMBOL_FILLING_IOC)!=0) { policy=ORDER_FILLING_IOC; return true; }
   if(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_EXEMODE)==SYMBOL_TRADE_EXECUTION_MARKET)
      return false;
   policy=ORDER_FILLING_RETURN;
   return true;
  }
bool OpenLeg(const int dir,const int leg,const double stop,const datetime signal)
  {
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q)) { Log("SKIP","no quote"); return false; }
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=_Point;
   double entry=dir>0?q.ask:q.bid;
   double minStop=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(dir>0?(stop>=q.bid-minStop):(stop<=q.ask+minStop))
     { Log("SKIP","broker stop distance signal="+IntegerToString((long)signal)); return false; }
   double riskPct=(InpExit==EXIT_FIXED_R?InpSymbolRiskPct:InpSymbolRiskPct/2.0);
   if(InpStageEnabled)
      riskPct=(leg==1?InpSymbolRiskPct*STAGE_PROBE_FRACTION:InpSymbolRiskPct);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double cap=equity*InpSymbolRiskPct/100.0*0.90;
   double budget=MathMin(equity*riskPct/100.0*0.90,cap-OpenStopRisk());
   double volume=budget>0?RiskVolume(dir,entry,stop,budget):0;
   if(volume<=0) { Log("SKIP","minimum volume exceeds risk signal="+IntegerToString((long)signal)); return false; }
   double target=0;
   if(leg!=1)
      target=dir>0?GridUp(entry+InpFixedTargetR*(entry-stop),tick):
                   GridDown(entry-InpFixedTargetR*(stop-entry),tick);
   ENUM_ORDER_TYPE_FILLING policy;
   if(!Filling(policy)) { Log("ERROR","unsupported filling mode"); return false; }
   MqlTradeRequest req={}; MqlTradeCheckResult chk={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.magic=LegMagic(leg);
   req.type=dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL; req.volume=volume;
   req.price=entry; req.sl=stop; req.tp=target; req.type_filling=policy;
   req.deviation=20; req.comment="TRR:"+IntegerToString(leg)+":"+IntegerToString((long)signal);
   if(!OrderCheck(req,chk) || (chk.retcode!=0 && chk.retcode!=TRADE_RETCODE_DONE))
     { Log("SKIP","order check leg="+IntegerToString(leg)+" code="+IntegerToString((int)chk.retcode)+" "+chk.comment); return false; }
   if(!OrderSend(req,res) || (res.retcode!=TRADE_RETCODE_DONE && res.retcode!=TRADE_RETCODE_DONE_PARTIAL))
     { Log("SKIP","order send leg="+IntegerToString(leg)+" code="+IntegerToString((int)res.retcode)+" "+res.comment); return false; }
   Log("ORDER","leg="+IntegerToString(leg)+" signal="+IntegerToString((long)signal)+
       " dir="+IntegerToString(dir)+" requested="+Num(entry,_Digits)+
       " stop="+Num(stop,_Digits)+" target="+Num(target,_Digits)+
       " lots="+Num(volume,4)+" spread="+Num(q.ask-q.bid,_Digits)+
       " deal="+IntegerToString((long)res.deal));
   return true;
  }
bool CloseLeg(const int leg,const string reason)
  {
   ulong ticket;
   if(!OwnLeg(leg,ticket)) return true;
   long positionId=PositionGetInteger(POSITION_IDENTIFIER);
   int trace=TraceIndex(positionId);
   if(trace>=0) g_trace[trace].exitRule=reason;
   int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
   double volume=PositionGetDouble(POSITION_VOLUME);
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return false;
   ENUM_ORDER_TYPE_FILLING policy; if(!Filling(policy)) return false;
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.position=ticket;
   req.magic=LegMagic(leg); req.type=dir>0?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
   req.volume=volume; req.price=dir>0?q.bid:q.ask; req.type_filling=policy;
   req.deviation=20; req.comment="TRR_EXIT:"+reason;
   if(!OrderSend(req,res) || (res.retcode!=TRADE_RETCODE_DONE && res.retcode!=TRADE_RETCODE_DONE_PARTIAL))
     { Log("ERROR","close leg="+IntegerToString(leg)+" reason="+reason+" code="+IntegerToString((int)res.retcode)); return false; }
   Log("CLOSE","leg="+IntegerToString(leg)+" reason="+reason+" ticket="+IntegerToString((long)ticket));
   return true;
  }
void UpdateExcursions()
  {
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      int magic=(int)PositionGetInteger(POSITION_MAGIC);
      if(magic<LegMagic(1) || magic>LegMagic(3)) continue;
      int index=TraceIndex(PositionGetInteger(POSITION_IDENTIFIER));
      if(index<0) continue;
      double price=g_trace[index].dir>0?q.bid:q.ask;
      if(g_trace[index].dir*(price-g_trace[index].best)>0) g_trace[index].best=price;
     }
  }
// Update the broker-side runner stop only. R is frozen at the original fill/stop.
void ManageRunner()
  {
   if(InpRunnerManagement==0) return;
   ulong ticket=0; if(!OwnLeg(1,ticket)) return;
   long id=PositionGetInteger(POSITION_IDENTIFIER);
   int i=TraceIndex(id); if(i<0) return;
   if(id!=g_manageId)
     { g_manageId=id; g_beTriggered=false; g_trailTriggered=false;
       g_manageBar=0; g_lastManageAttempt=0; g_lastInvalidLog=0; g_trailCandidate=0; }
   MqlTick q; if(!SymbolInfoTick(_Symbol,q)) return;
   int dir=g_trace[i].dir;
   double risk=MathAbs(g_trace[i].entry-g_trace[i].stop);
   if(risk<=0) return;
   double move=dir*((dir>0?q.bid:q.ask)-g_trace[i].entry)/risk;
   if(!g_beTriggered && move>=2.0)
     { g_beTriggered=true; Log("BE_TRIGGER","id="+IntegerToString(id)+" moveR="+Num(move,4)); }
   if(InpRunnerManagement==2 && !g_trailTriggered && move>=5.0)
     { g_trailTriggered=true; Log("TRAIL_TRIGGER","id="+IntegerToString(id)+" moveR="+Num(move,4)); }
   if(!g_beTriggered) return;
   datetime bar=iTime(_Symbol,PERIOD_M15,0);
   if(g_trailTriggered && (bar!=g_manageBar || g_manageBar==0))
     {
      g_manageBar=bar;
      MqlRates rr[]; ArraySetAsSeries(rr,false);
      int n=CopyRates(_Symbol,PERIOD_M15,g_trace[i].entryTime,bar-1,rr);
      double atr[]; ArraySetAsSeries(atr,true);
      if(n>0 && CopyBuffer(g_atrHandle,0,1,1,atr)==1 && atr[0]>0)
        {
         double extreme=0;
         for(int j=0;j<n;j++)
           if(rr[j].time>=g_trace[i].entryTime && rr[j].time+PeriodSeconds(PERIOD_M15)<=bar)
             { if(extreme==0) extreme=dir>0?rr[j].high:rr[j].low;
               else extreme=dir>0?MathMax(extreme,rr[j].high):MathMin(extreme,rr[j].low); }
         if(extreme>0) g_trailCandidate=extreme-dir*3.0*atr[0];
        }
     }
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); if(tick<=0) tick=_Point;
   double desired=g_trace[i].entry;
   if(g_trailTriggered && g_trailCandidate>0)
      desired=dir>0?MathMax(desired,g_trailCandidate):MathMin(desired,g_trailCandidate);
   desired=dir>0?GridDown(desired,tick):GridUp(desired,tick);
   double existing=PositionGetDouble(POSITION_SL);
   if(existing>0 && dir*(desired-existing)<tick*0.5) return;
   long stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double distance=MathMax(stops,freeze)*_Point;
   bool valid=dir>0?(desired<q.bid-distance):(desired>q.ask+distance);
   if(!valid)
     { if(TimeCurrent()-g_lastInvalidLog>=60)
         { Log("STOP_DEFER","id="+IntegerToString(id)+" desired="+Num(desired,_Digits)+" bid="+Num(q.bid,_Digits)+" ask="+Num(q.ask,_Digits)+" stops="+IntegerToString(stops)+" freeze="+IntegerToString(freeze)); g_lastInvalidLog=TimeCurrent(); }
       // If a trail is temporarily too close to market, still attempt the
       // independent break-even protection when it is broker-valid.
       double be=dir>0?GridDown(g_trace[i].entry,tick):GridUp(g_trace[i].entry,tick);
       bool beImproves=existing<=0 || dir*(be-existing)>=tick*0.5;
       bool beValid=dir>0?(be<q.bid-distance):(be>q.ask+distance);
       if(!beImproves || !beValid) return;
       desired=be;
     }
   if(TimeCurrent()==g_lastManageAttempt) return;
   g_lastManageAttempt=TimeCurrent();
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_SLTP; req.position=ticket; req.symbol=_Symbol;
   req.sl=desired; req.tp=PositionGetDouble(POSITION_TP);
   bool sent=OrderSend(req,res);
   bool ok=sent && res.retcode==TRADE_RETCODE_DONE;
   Log(ok?"STOP_MODIFIED":"STOP_REJECTED","id="+IntegerToString(id)+" leg=1 old="+Num(existing,_Digits)+" desired="+Num(desired,_Digits)+" bid="+Num(q.bid,_Digits)+" ask="+Num(q.ask,_Digits)+" code="+IntegerToString((int)res.retcode)+" trail="+(g_trailTriggered?"1":"0"));
  }
void SnapshotMonth()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt); int month=dt.year*100+dt.mon;
   if(month==g_snapshotMonth) return;
   g_snapshotMonth=month;
   Log("MONTH_SNAPSHOT","month="+IntegerToString(month)+" balance="+Num(AccountInfoDouble(ACCOUNT_BALANCE),2)+" equity="+Num(AccountInfoDouble(ACCOUNT_EQUITY),2)+" positions="+IntegerToString(PositionsTotal()));
  }
int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
   if(InpRunnerManagement<0 || InpRunnerManagement>2) return INIT_PARAMETERS_INCORRECT;
   g_atrHandle=iATR(_Symbol,PERIOD_M15,14);
   if(g_atrHandle==INVALID_HANDLE) return INIT_FAILED;
   if(InpMagic<1000 || InpSymbolRiskPct<=0 || InpSymbolRiskPct>3 ||
      InpFixedTargetR<0.5 || InpFixedTargetR>3.0 ||
      (InpSignalTrigger!=SIGNAL_VWAP_CROSS && InpSignalTrigger!=SIGNAL_EMA_RECLAIM) ||
      (InpStageEnabled && (InpEntry!=ENTRY_M1_M5_ONLY ||
                           InpM5OnlySignalTf!=PERIOD_M1 || InpExit==EXIT_FIXED_R)) ||
      (InpM5OnlySignalTf!=PERIOD_M1 && InpM5OnlySignalTf!=PERIOD_M3 &&
       InpM5OnlySignalTf!=PERIOD_M5 && InpM5OnlySignalTf!=PERIOD_M15) ||
      InpBandEmaPeriod<2 || InpBandEmaPeriod>100 ||
      InpVwapSmoothPeriod<2 || InpVwapSmoothPeriod>100 ||
      InpMajorEmaPeriod<50 || InpMajorEmaPeriod>500 ||
      InpTrendSlopeBars<1 || InpTrendSlopeBars>12 ||
      (InpScreenHistoryBars!=0 &&
       (InpScreenHistoryBars<InpMajorEmaPeriod+60 || InpScreenHistoryBars>6000)) ||
      (InpEntry!=ENTRY_SWING_CONTROL && InpEntry!=ENTRY_M15_BAND &&
       InpEntry!=ENTRY_M1_M5_M15 && InpEntry!=ENTRY_M1_M5_ONLY) ||
      (InpStopBand!=STOP_SIGNAL_BAND && InpStopBand!=STOP_M3_BAND && InpStopBand!=STOP_M5_BAND) ||
      (InpTrend!=TREND_H1 && InpTrend!=TREND_H4) ||
      (InpExit!=EXIT_FIXED_R && InpExit!=EXIT_RUNNER && InpExit!=EXIT_BAND_RUNNER))
      return INIT_PARAMETERS_INCORRECT;
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     { Print("TRR requires hedging account"); return INIT_FAILED; }
   g_file="TrenderRunner_"+InpRunId+".csv";
   int h=FileOpen(g_file,FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI,';');
   if(h==INVALID_HANDLE) return INIT_FAILED;
   FileWrite(h,"time","kind","detail"); FileClose(h);
   g_lastM1=iTime(_Symbol,PERIOD_M1,0);
   g_lastM3=iTime(_Symbol,PERIOD_M3,0);
   g_lastM5=iTime(_Symbol,PERIOD_M5,0);
   g_lastM15=iTime(_Symbol,PERIOD_M15,0);
   g_lastSignalM15=g_lastM15;
   g_stageLastM1=g_lastM1;
   if(Visual()) ChartSetInteger(0,CHART_SHOW_GRID,false);
   Log("START","entry="+IntegerToString((int)InpEntry)+
       " stopTf="+StopText()+
       " signalTf="+EnumToString(InpM5OnlySignalTf)+
       " signalTrigger="+IntegerToString((int)InpSignalTrigger)+
       " bandEma="+IntegerToString(InpBandEmaPeriod)+
       " vwapSmooth="+IntegerToString(InpVwapSmoothPeriod)+
       " majorEma="+IntegerToString(InpMajorEmaPeriod)+
       " slopeBars="+IntegerToString(InpTrendSlopeBars)+
       " historyBars="+IntegerToString(InpScreenHistoryBars)+
       " trend="+IntegerToString((int)InpTrend)+" exit="+IntegerToString((int)InpExit)+
       " fixedTargetR="+DoubleToString(InpFixedTargetR,2)+
       " stage="+(InpStageEnabled?"1":"0")+
       " independentFixed="+(InpIndependentFixed?"1":"0"));
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  { Log("END","reason="+IntegerToString(reason)+" signals="+IntegerToString(g_signals)); }
void ActivateWarning(const string reason,const string detail)
  {
   if(!g_runnerWarning || g_warningReason!=reason)
      Log("WARNING_ON","reason="+reason+" "+detail);
   g_runnerWarning=true; g_warningReason=reason;
  }
void ClearWarning(const string detail)
  {
   if(g_runnerWarning) Log("WARNING_CLEAR","prior="+g_warningReason+" "+detail);
   g_runnerWarning=false; g_warningReason="none";
  }
void TryStageAdd()
  {
   if(!InpStageEnabled || g_stageSignal<=0) return;
   datetime currentM1=iTime(_Symbol,PERIOD_M1,0);
   if(currentM1<=0 || currentM1==g_stageLastM1) return;
   g_stageLastM1=currentM1;
   ulong core=0,satellite=0;
   if(!OwnLeg(1,core) || OwnLeg(2,satellite))
     { g_stageSignal=0; return; }
   if(TimeCurrent()>g_stageStarted+STAGE_WINDOW_SECONDS)
     {
      Log("STAGE_EXPIRE","signal="+IntegerToString((long)g_stageSignal)+" no confirmation");
      g_stageSignal=0;
      return;
     }
   MqlRates closed[];
   if(CopyRates(_Symbol,PERIOD_M1,1,1,closed)!=1 ||
      closed[0].time<g_stageStarted ||
      closed[0].time+PeriodSeconds(PERIOD_M1)>TimeCurrent()) return;
   if(!PositionSelectByTicket(core)) return;
   int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double stop=PositionGetDouble(POSITION_SL);
   double risk=MathAbs(entry-stop);
   if(risk<=0 || dir*(closed[0].close-entry)<STAGE_CONFIRM_R*risk) return;
   datetime signal=g_stageSignal;
   Log("STAGE_CONFIRM","signal="+IntegerToString((long)signal)+
       " closedBar="+IntegerToString((long)closed[0].time)+
       " close="+Num(closed[0].close,_Digits)+
       " moveR="+DoubleToString(dir*(closed[0].close-entry)/risk,3));
   if(OpenLeg(dir,2,stop,signal))
      Log("STAGE_ADD","signal="+IntegerToString((long)signal)+
          " riskOpen="+DoubleToString(OpenStopRisk(),2));
   else Log("STAGE_ADD_SKIP","signal="+IntegerToString((long)signal));
   g_stageSignal=0;
  }
void RefreshInformation(BandContext &m15,BandContext &h1Band,BandContext &h4Band)
  {
   BuildBandContext(PERIOD_M15,m15);
   BuildBandContext(PERIOD_H1,h1Band);
   BuildBandContext(PERIOD_H4,h4Band);
   int d=0; double h=0,l=0,ph=0,pl=0;
   StructureDetail(PERIOD_M15,-1,d,h,l,ph,pl);
   g_panelM15Shape=ShapeText(h,ph,l,pl);
   g_panelM15=m15.ready?m15.dir:0;
   g_panelM15State=m15.ready?m15.state:BAND_UNKNOWN;
   g_panelM15Width=m15.widthATR; g_panelM15Median=m15.median; g_panelM15Q25=m15.q25;
   StructureDetail(PERIOD_H1,-1,d,h,l,ph,pl); g_panelH1=d;
   g_panelH1Shape=ShapeText(h,ph,l,pl)+" band "+DirectionText(h1Band.dir)+
                  " EMA "+(h1Band.close>h1Band.ema200?"above":"below");
   StructureDetail(PERIOD_H4,-1,d,h,l,ph,pl); g_panelH4=d;
   g_panelH4Shape=ShapeText(h,ph,l,pl)+" band "+DirectionText(h4Band.dir)+
                  " EMA "+(h4Band.close>h4Band.ema200?"above":"below");
  }
void OnTick()
  {
   UpdateExcursions();
   SnapshotMonth();
   ManageRunner();
   if(InpExit!=EXIT_FIXED_R)
     {
      ulong orphanCore=0,orphanSat=0;
      bool coreExists=OwnLeg(1,orphanCore),satExists=OwnLeg(2,orphanSat);
      if(!InpIndependentFixed && !coreExists && satExists) CloseLeg(2,"RUNNER_ENDED");
      if(!coreExists && g_runnerWarning) ClearWarning("runner no longer open");
     }
   datetime m15=iTime(_Symbol,PERIOD_M15,0);
   if(m15>0 && m15!=g_lastM15)
     {
      g_lastM15=m15;
      BandContext m15Band,h1Band,h4Band;
      RefreshInformation(m15Band,h1Band,h4Band);
      if(m15Band.ready)
        {
         Log("M15_STATE",BandFields("m15",m15Band));
         if(m15Band.state==BAND_REEXPANDING)
            Log("REEXPANSION",BandFields("m15",m15Band));
        }
      ulong core;
      if(InpExit==EXIT_RUNNER && OwnLeg(1,core))
        {
         int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
         MqlRates r[]; int n=Rates(PERIOD_M15,STRUCTURE_COUNT,r);
         int priorDir=0; double high=0,low=0;
         if(n>10 && Structure(PERIOD_M15,n-3,priorDir,high,low))
           {
            double closed=r[n-2].close;
            bool broken=dir>0?(low>0 && closed<low):(high>0 && closed>high);
            if(broken)
              {
               Log("STRUCTURE","M15 closed="+Num(closed,_Digits)+" priorLow="+
                   Num(low,_Digits)+" priorHigh="+Num(high,_Digits));
               if(CloseLeg(1,"M15_STRUCTURE") && !InpIndependentFixed) CloseLeg(2,"M15_STRUCTURE");
              }
           }
        }
      else if(InpExit==EXIT_BAND_RUNNER && OwnLeg(1,core) && m15Band.ready)
        {
         int dir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
         MqlRates r[]; int n=Rates(PERIOD_M15,STRUCTURE_COUNT,r);
         int priorDir=0; double high=0,low=0;
         if(n>10 && Structure(PERIOD_M15,n-3,priorDir,high,low))
           {
            double closed=r[n-2].close;
            bool broken=dir>0?(low>0 && closed<low):(high>0 && closed>high);
            if(broken) ActivateWarning("M15_STRUCTURE","closed="+Num(closed,_Digits)+
                                      " priorLow="+Num(low,_Digits)+" priorHigh="+Num(high,_Digits));
           }
         if(m15Band.state==BAND_CONTRACTING)
            ActivateWarning("M15_CONTRACTING",BandFields("m15",m15Band));
         if(m15Band.state==BAND_COMPRESSED)
            ActivateWarning("M15_COMPRESSED",BandFields("m15",m15Band));
         if(g_runnerWarning && m15Band.dir==dir &&
            (m15Band.state==BAND_EXPANDING || m15Band.state==BAND_REEXPANDING))
            ClearWarning("reason=M15_REEXPANSION "+BandFields("m15",m15Band));
         bool adverseBand=dir>0?m15Band.close<MathMin(m15Band.emaLow,m15Band.smoothVwap):
                                     m15Band.close>MathMax(m15Band.emaLow,m15Band.smoothVwap);
         bool emaCross=dir>0?(m15Band.previousClose>=m15Band.previousEMA200 &&
                              m15Band.close<m15Band.ema200):
                             (m15Band.previousClose<=m15Band.previousEMA200 &&
                              m15Band.close>m15Band.ema200);
         string exitReason="";
         if(emaCross) exitReason="M15_EMA200_CROSS";
         else if(adverseBand) exitReason=g_runnerWarning &&
                 (m15Band.state==BAND_CONTRACTING || m15Band.state==BAND_COMPRESSED)?
                 "M15_WARNING_BAND_CROSS":"M15_BAND_CROSS";
         if(exitReason!="")
           {
            Log("RUNNER_EXIT","reason="+exitReason+" warning="+(g_runnerWarning?"1":"0")+
                " "+BandFields("m15",m15Band));
            if(CloseLeg(1,exitReason) && !InpIndependentFixed) CloseLeg(2,exitReason);
            ClearWarning("runner exit="+exitReason);
           }
        }
     }
   TryStageAdd();
   ENUM_TIMEFRAMES signalTf=InpEntry==ENTRY_M1_M5_ONLY?InpM5OnlySignalTf:
                            (InpEntry==ENTRY_M1_M5_M15?PERIOD_M1:PERIOD_M5);
   datetime signalOpen=iTime(_Symbol,signalTf,0);
   if(signalOpen<=0) return;
   if(signalTf==PERIOD_M1)
     {
      if(signalOpen==g_lastM1) return;
      g_lastM1=signalOpen;
     }
   else if(signalTf==PERIOD_M3)
     {
      if(signalOpen==g_lastM3) return;
      g_lastM3=signalOpen;
     }
   else if(signalTf==PERIOD_M15)
     {
      if(signalOpen==g_lastSignalM15) return;
      g_lastSignalM15=signalOpen;
     }
   else
     {
      if(signalOpen==g_lastM5) return;
      g_lastM5=signalOpen;
     }
   BandContext signalBand,m5Band,m15Band,h1Band,h4Band;
   BuildBandContext(signalTf,signalBand);
   BuildBandContext(PERIOD_M5,m5Band);
   RefreshInformation(m15Band,h1Band,h4Band);
   g_panelM5=m5Band.ready?m5Band.dir:0;
   g_panelM5State=m5Band.ready?m5Band.state:BAND_UNKNOWN;
   int dir=0; double outer=0,a=0,b=0,ema200=0; datetime signal=0;
   bool arrow=ArrowAt(signalTf,dir,outer,a,b,ema200,signal);
   if(signal>0) BandSegment(signal,a,b,ema200,g_bandSide);
   if(Visual())
     {
      g_panelArrow=arrow?(EnumToString(signalTf)+" "+(dir>0?"BUY":"SELL")):"none";
      if(!arrow) g_lastDecision="waiting for a closed "+EnumToString(signalTf)+" arrow";
      Panel();
     }
   if(!arrow) return;
   g_signals++;
   Log("SIGNAL","id="+IntegerToString(g_signals)+" bar="+IntegerToString((long)signal)+
       " dir="+IntegerToString(dir)+" bandA="+Num(a,8)+" bandB="+Num(b,8)+
       " signalTf="+IntegerToString((int)signalTf)+" "+BandFields("signal",signalBand)+
       " "+BandFields("m5",m5Band)+" "+BandFields("m15",m15Band));
   int m15Dir=0,htfDir=0,h1Dir=0,h4Dir=0;
   double mh=0,ml=0,hh=0,hl=0,mph=0,mpl=0,hph=0,hpl=0;
   double h1h=0,h1l=0,h1ph=0,h1pl=0,h4h=0,h4l=0,h4ph=0,h4pl=0;
   bool m15Ready=StructureDetail(PERIOD_M15,-1,m15Dir,mh,ml,mph,mpl);
   bool htfReady=StructureDetail(InpTrend==TREND_H1?PERIOD_H1:PERIOD_H4,-1,htfDir,hh,hl,hph,hpl);
   StructureDetail(PERIOD_H1,-1,h1Dir,h1h,h1l,h1ph,h1pl);
   StructureDetail(PERIOD_H4,-1,h4Dir,h4h,h4l,h4ph,h4pl);
   bool aligned=false;
   ulong visibleCore=0;
   if(OwnLeg(1,visibleCore) && PositionSelectByTicket(visibleCore))
      Level("TRR_M15_BREAK",PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?ml:mh,clrMediumPurple);
   else if(Visual()) ObjectDelete(0,"TRR_M15_BREAK");
   bool hasVisibleCore=OwnLeg(1,visibleCore);
   string blockReason="";
   if(InpEntry==ENTRY_SWING_CONTROL)
      aligned=m15Ready && htfReady && m15Dir==dir && htfDir==dir;
   else if(InpEntry==ENTRY_M15_BAND)
     {
      aligned=m15Band.ready && m15Band.dir==dir;
      if(!aligned) blockReason="M15_DIRECTION";
      else if(m15Band.state==BAND_EXPANDING || m15Band.state==BAND_REEXPANDING) { }
      else if(hasVisibleCore && m15Band.state==BAND_MATURE && m5Band.ready &&
              (m5Band.state==BAND_EXPANDING || m5Band.state==BAND_REEXPANDING)) { }
      else
        {
         aligned=false;
         blockReason="M15_"+BandStateText(m15Band.state);
        }
     }
   else if(InpEntry==ENTRY_M1_M5_M15)
     {
      aligned=signalBand.ready && m5Band.ready && m15Band.ready &&
              m5Band.dir==dir && m15Band.dir==dir;
      if(!aligned) blockReason="M5_M15_DIRECTION";
      else if(hasVisibleCore &&
              (m15Band.state==BAND_CONTRACTING || m15Band.state==BAND_COMPRESSED))
        {
         aligned=false;
         blockReason="M15_"+BandStateText(m15Band.state);
        }
     }
   else
     {
      aligned=signalBand.ready && m5Band.ready && m5Band.dir==dir;
      if(!aligned) blockReason="M5_DIRECTION";
      else if(hasVisibleCore &&
              (m5Band.state==BAND_CONTRACTING || m5Band.state==BAND_COMPRESSED))
        {
         aligned=false;
         blockReason="M5_"+BandStateText(m5Band.state);
        }
     }
   if(aligned)
      Mark("TRR_SIGNAL_"+IntegerToString((long)signal),signal,
           dir>0?outer-3*_Point:outer+3*_Point,dir>0?233:234,
           dir>0?clrLime:clrRed,"Eligible closed "+EnumToString(signalTf)+" arrow");
   Log("FILTER","signal="+IntegerToString((long)signal)+
       " entry="+IntegerToString((int)InpEntry)+" stopTf="+StopText()+
       " eligible="+(aligned?"1":"0")+
       " block="+(blockReason==""?"none":blockReason)+
       " m15Swing="+IntegerToString(m15Dir)+" selectedHtf="+IntegerToString(htfDir)+
       " h1Swing="+IntegerToString(h1Dir)+" h4Swing="+IntegerToString(h4Dir)+
       " h1EmaSide="+IntegerToString(h1Band.close>h1Band.ema200?1:-1)+
       " h4EmaSide="+IntegerToString(h4Band.close>h4Band.ema200?1:-1)+
       " "+BandFields("signal",signalBand)+" "+BandFields("m5",m5Band)+" "+BandFields("m15",m15Band)+
       " "+BandFields("h1",h1Band)+" "+BandFields("h4",h4Band));
   if(!aligned)
     {
      if(InpEntry!=ENTRY_SWING_CONTROL && hasVisibleCore)
         Log("BLOCKED_ADD","signal="+IntegerToString((long)signal)+" reason="+blockReason+
             " "+BandFields("m15",m15Band)+" "+BandFields("m5",m5Band)+
             " "+BandFields("signal",signalBand));
      else Log("SKIP","entry filter signal="+IntegerToString((long)signal)+" reason="+blockReason);
      return;
     }
   Log("ELIGIBLE","signal="+IntegerToString((long)signal)+" dir="+IntegerToString(dir)+
       " entry="+IntegerToString((int)InpEntry)+" m15State="+IntegerToString(m15Band.state)+
       " m5State="+IntegerToString(m5Band.state)+" signalState="+IntegerToString(signalBand.state));
   BandContext stopBand;
   ENUM_TIMEFRAMES stopTf=signalTf;
   if(InpStopBand==STOP_M3_BAND) stopTf=PERIOD_M3;
   if(InpStopBand==STOP_M5_BAND) stopTf=PERIOD_M5;
   if(stopTf==signalTf) stopBand=signalBand;
   else if(stopTf==PERIOD_M5) stopBand=m5Band;
   else BuildBandContext(stopTf,stopBand);
   if(!stopBand.ready || stopBand.time<=0 ||
      stopBand.time+PeriodSeconds(stopTf)>signalOpen)
     {
      Log("SKIP","stop band unavailable or incomplete signal="+IntegerToString((long)signal)+
          " stopTf="+StopText());
      return;
     }
   double stopOuter=dir>0?MathMin(stopBand.emaLow,stopBand.smoothVwap):
                            MathMax(stopBand.emaLow,stopBand.smoothVwap);
   g_lastStopBandA=stopBand.emaLow; g_lastStopBandB=stopBand.smoothVwap;
   g_lastStopBandTime=stopBand.time;
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=_Point;
   // Round the band edge to the broker grid first, then move exactly one tick outside it.
   double stop=dir>0?NormalizeDouble(GridDown(stopOuter,tick)-tick,_Digits):
                     NormalizeDouble(GridUp(stopOuter,tick)+tick,_Digits);
   Log("STOP_BAND","signal="+IntegerToString((long)signal)+" source="+StopText()+
       " sourceBar="+IntegerToString((long)stopBand.time)+
       " outer="+Num(stopOuter,_Digits)+" stop="+Num(stop,_Digits)+
       " stopA="+Num(stopBand.emaLow,8)+" stopB="+Num(stopBand.smoothVwap,8));
   ulong core=0,sat=0,base=0;
   if(InpExit==EXIT_FIXED_R)
     {
      if(OwnLeg(3,base)) { Log("SKIP","baseline busy"); return; }
      OpenLeg(dir,3,stop,signal);
      return;
     }
   bool hasCore=OwnLeg(1,core),hasSat=OwnLeg(2,sat);
   if(!hasCore && hasSat) { Log("SKIP","satellite remains after core"); return; }
   if(InpStageEnabled)
     {
      if(hasCore) { Log("SKIP","staged core occupied"); return; }
      if(!OpenLeg(dir,1,stop,signal)) return;
      g_stageSignal=signal;
      g_stageStarted=TimeCurrent();
      g_stageLastM1=iTime(_Symbol,PERIOD_M1,0);
      Log("STAGE_PROBE","signal="+IntegerToString((long)signal)+
          " started="+IntegerToString((long)g_stageStarted)+
          " fraction="+DoubleToString(STAGE_PROBE_FRACTION,2));
      return;
     }
   if(hasCore)
     {
      PositionSelectByTicket(core);
      int coreDir=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
      if(coreDir!=dir || hasSat) { Log("SKIP","runner direction or satellite occupied"); return; }
      OpenLeg(dir,2,stop,signal);
      return;
     }
   // Starting both legs is all-or-none; a failed satellite is followed by closing the core.
   if(!OpenLeg(dir,1,stop,signal)) return;
   if(!OpenLeg(dir,2,stop,signal)) CloseLeg(1,"PAIR_FAILED");
  }
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   long magic=HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   int leg=(int)(magic-(long)InpMagic);
   if(leg<1 || leg>3) return;
   long id=HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   int entryType=(int)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   double price=HistoryDealGetDouble(trans.deal,DEAL_PRICE);
   double volume=HistoryDealGetDouble(trans.deal,DEAL_VOLUME);
   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   double commission=HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   double swap=HistoryDealGetDouble(trans.deal,DEAL_SWAP);
   if(entryType==DEAL_ENTRY_IN)
     {
      int dir=HistoryDealGetInteger(trans.deal,DEAL_TYPE)==DEAL_TYPE_BUY?1:-1;
      double stop=0,target=0;
      ulong order=(ulong)HistoryDealGetInteger(trans.deal,DEAL_ORDER);
      if(HistoryOrderSelect(order))
        { stop=HistoryOrderGetDouble(order,ORDER_SL); target=HistoryOrderGetDouble(order,ORDER_TP); }
      if(stop<=0 && PositionSelectByTicket(trans.position))
        { stop=PositionGetDouble(POSITION_SL); target=PositionGetDouble(POSITION_TP); }
      int index=TraceIndex(id);
      if(index<0)
        {
         index=ArraySize(g_trace); ArrayResize(g_trace,index+1);
         g_trace[index].id=id; g_trace[index].dir=dir; g_trace[index].leg=leg;
         g_trace[index].entry=price; g_trace[index].stop=stop;
         g_trace[index].target=target; g_trace[index].best=price;
         g_trace[index].entryTime=TimeCurrent(); g_trace[index].volume=volume;
         double riskAmount=0;
         ENUM_ORDER_TYPE riskType=dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
         if(OrderCalcProfit(riskType,_Symbol,volume,price,stop,riskAmount))
            g_trace[index].riskUSD=MathMax(0,-riskAmount);
         g_trace[index].exitRule="";
        }
      Log("FILL","id="+IntegerToString(id)+" leg="+IntegerToString(leg)+
          " deal="+IntegerToString((long)trans.deal)+" entry="+Num(price,_Digits)+
          " stop="+Num(stop,_Digits)+" target="+Num(target,_Digits)+
          " volume="+Num(volume,4)+" profit="+Num(profit,2)+
          " commission="+Num(commission,2)+" swap="+Num(swap,2)+
          " riskUSD="+Num(g_trace[index].riskUSD,2));
      Mark("TRR_ENTRY_"+IntegerToString(id),TimeCurrent(),price,dir>0?233:234,
           leg==1?clrAqua:clrGold,"Entry leg="+IntegerToString(leg)+
           " stop="+Num(stop,_Digits)+" target="+Num(target,_Digits));
      Level("TRR_ACTIVE_STOP_"+IntegerToString(leg),stop,clrTomato);
      if(target>0) Level("TRR_ACTIVE_TARGET_"+IntegerToString(leg),target,clrGold);
     }
   else if(entryType==DEAL_ENTRY_OUT || entryType==DEAL_ENTRY_OUT_BY)
     {
      int index=TraceIndex(id); double mfe=0,giveback=0,hold=0;
      if(index>=0)
        {
         double risk=MathAbs(g_trace[index].entry-g_trace[index].stop);
         double best=MathMax(0,g_trace[index].dir*(g_trace[index].best-g_trace[index].entry));
         double realized=g_trace[index].dir*(price-g_trace[index].entry);
         if(realized>best) best=realized;
         if(risk>0) { mfe=best/risk; giveback=(best-realized)/risk; }
         hold=(double)(TimeCurrent()-g_trace[index].entryTime)/60.0;
        }
      string rule=index>=0?g_trace[index].exitRule:"";
      if(rule=="")
        {
         int dealReason=(int)HistoryDealGetInteger(trans.deal,DEAL_REASON);
         rule=dealReason==DEAL_REASON_SL?"SL":dealReason==DEAL_REASON_TP?"TP":"external";
        }
      Log("EXIT","id="+IntegerToString(id)+" leg="+IntegerToString(leg)+
          " deal="+IntegerToString((long)trans.deal)+" exit="+Num(price,_Digits)+
          " volume="+Num(volume,4)+
          " profit="+Num(profit,2)+" commission="+Num(commission,2)+
          " swap="+Num(swap,2)+" mfeR="+Num(mfe,4)+
          " givebackR="+Num(giveback,4)+" holdMin="+Num(hold,2)+
          " reason="+IntegerToString((int)HistoryDealGetInteger(trans.deal,DEAL_REASON))+
          " exitRule="+rule);
      Mark("TRR_EXIT_"+IntegerToString(id),TimeCurrent(),price,251,
           leg==1?clrAqua:clrGold,"Exit leg="+IntegerToString(leg)+
           " MFE="+Num(mfe,2)+"R giveback="+Num(giveback,2)+"R");
      if(Visual())
        {
         ObjectDelete(0,"TRR_ACTIVE_STOP_"+IntegerToString(leg));
         ObjectDelete(0,"TRR_ACTIVE_TARGET_"+IntegerToString(leg));
        }
     }
  }
