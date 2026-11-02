// Test-only Simple Trender research EA.
// Compare identical M15 stop-entry mechanics with and without an H4 trend scan.
// Refuses to initialize outside the MT5 Strategy Tester.
#property strict
#property version "1.000"

input group "Research run"
input int    InpMode=1;                // 0=M15 arrow only, 1=H4 scan + M15 arrow
input string InpRunId="research";
input ulong  InpMagic=26102715;
input double InpRiskPct=0.5;
input double InpTargetR=2.0;
input int    InpExpiryM15Bars=2;
input double InpMaxSpreadRiskFraction=0.10;
input double InpMaxBandDistanceATR=0.50;

#define H4_BARS 320
#define M15_BARS 1600
#define EMA_LOW_LENGTH 26
#define VWAP_EMA_LENGTH 13
#define SCAN_BARS 12
#define ATR_BARS 14

MqlRates g_h4[],g_m15[];
datetime g_lastM15=0,g_lastH4=0,g_pendingExpiry=0;
ulong g_pendingTicket=0;
string g_file="";

double Max3(const double a,const double b,const double c)
  { return MathMax(a,MathMax(b,c)); }
double Min3(const double a,const double b,const double c)
  { return MathMin(a,MathMin(b,c)); }
double GridUp(const double value,const double tick)
  { return NormalizeDouble(MathCeil(value/tick-1e-9)*tick,_Digits); }
double GridDown(const double value,const double tick)
  { return NormalizeDouble(MathFloor(value/tick+1e-9)*tick,_Digits); }
string Num(const double value,const int digits=3)
  { return DoubleToString(value,digits); }
string DirName(const int dir)
  { return dir>0?"BUY":dir<0?"SELL":"NONE"; }
int DayKey(const datetime when)
  {
   MqlDateTime v;
   TimeToStruct(when,v);
   return v.year*10000+v.mon*100+v.day;
  }
void Event(const string kind,const int dir,const double score,const string detail)
  {
   Print("TMR ",kind," ",_Symbol," ",DirName(dir)," score=",Num(score),": ",detail);
   int file=FileOpen(g_file,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,';');
   if(file==INVALID_HANDLE) return;
   FileSeek(file,0,SEEK_END);
   FileWrite(file,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
             _Symbol,kind,DirName(dir),Num(score,6),detail);
   FileClose(file);
  }
int Load(const ENUM_TIMEFRAMES tf,const int count,MqlRates &rates[])
  {
   ArrayFree(rates);
   ArraySetAsSeries(rates,false);
   return CopyRates(_Symbol,tf,0,count,rates);
  }
void EmaLow(const MqlRates &rates[],const int n,double &out[])
  {
   ArrayResize(out,n);
   double alpha=2.0/(EMA_LOW_LENGTH+1.0);
   for(int i=0;i<n;i++)
      out[i]=(i==0?rates[i].low:
              alpha*rates[i].low+(1.0-alpha)*out[i-1]);
  }
double RecentATR(const MqlRates &rates[],const int last)
  {
   if(last<ATR_BARS) return 0;
   double sum=0;
   for(int i=last-ATR_BARS+1;i<=last;i++)
      sum+=Max3(rates[i].high-rates[i].low,
                MathAbs(rates[i].high-rates[i-1].close),
                MathAbs(rates[i].low-rates[i-1].close));
   return sum/ATR_BARS;
  }
bool H4Scan(int &dir,double &score,double &efficiency,double &moveATR,string &why)
  {
   dir=0; score=0; efficiency=0; moveATR=0; why="";
   int n=Load(PERIOD_H4,H4_BARS,g_h4);
   if(n<EMA_LOW_LENGTH+SCAN_BARS+2)
     { why="insufficient H4 data"; return false; }
   int last=n-2;
   double ema[];
   EmaLow(g_h4,n,ema);
   double atr=RecentATR(g_h4,last);
   if(atr<=0) { why="invalid H4 ATR"; return false; }
   double change=g_h4[last].close-g_h4[last-SCAN_BARS].close;
   double path=0;
   for(int i=last-SCAN_BARS+1;i<=last;i++)
      path+=MathAbs(g_h4[i].close-g_h4[i-1].close);
   if(path<=0) { why="zero H4 movement"; return false; }
   efficiency=MathAbs(change)/path;
   moveATR=MathAbs(change)/atr;
   dir=change>0?1:change<0?-1:0;
   score=efficiency*MathMin(moveATR,4.0);
   if(dir==0 || efficiency<0.45 || moveATR<1.5)
     { why="H4 efficiency or distance below threshold"; return false; }
   if(dir*(g_h4[last].close-ema[last])<=0 ||
      dir*(g_h4[last-1].close-ema[last-1])<=0)
     { why="last two H4 closes oppose EMA-low"; return false; }
   why="H4 trend qualified";
   return true;
  }
bool M15Arrow(int &dir,double &distanceATR,double &signalHigh,
              double &signalLow,datetime &signalTime,string &why)
  {
   dir=0; distanceATR=0; signalHigh=0; signalLow=0; signalTime=0;
   int n=Load(PERIOD_M15,M15_BARS,g_m15);
   if(n<EMA_LOW_LENGTH+ATR_BARS+2)
     { why="insufficient M15 data"; return false; }
   int last=n-2;
   double ema[],smooth[];
   EmaLow(g_m15,n,ema);
   ArrayResize(smooth,n);
   double sumPV=0,sumVolume=0;
   int previousDay=0;
   double alpha=2.0/(VWAP_EMA_LENGTH+1.0);
   for(int i=0;i<n;i++)
     {
      int day=DayKey(g_m15[i].time);
      if(day!=previousDay) { sumPV=0; sumVolume=0; previousDay=day; }
      double volume=MathMax(1.0,(double)g_m15[i].tick_volume);
      double typical=(g_m15[i].high+g_m15[i].low+g_m15[i].close)/3.0;
      sumPV+=typical*volume;
      sumVolume+=volume;
      double vwap=sumPV/sumVolume;
      smooth[i]=(i==0?vwap:alpha*vwap+(1.0-alpha)*smooth[i-1]);
     }
   double close=g_m15[last].close;
   double prevClose=g_m15[last-1].close;
   if(close>ema[last] && prevClose<smooth[last] && close>smooth[last]) dir=1;
   if(close<ema[last] && prevClose>smooth[last] && close<smooth[last]) dir=-1;
   if(dir==0) { why="no closed M15 arrow"; return false; }
   double atr=RecentATR(g_m15,last);
   if(atr<=0) { why="invalid M15 ATR"; return false; }
   double edge=dir>0?MathMax(ema[last],smooth[last]):
                     MathMin(ema[last],smooth[last]);
   distanceATR=dir*(close-edge)/atr;
   signalHigh=g_m15[last].high;
   signalLow=g_m15[last].low;
   signalTime=g_m15[last].time;
   why="closed M15 "+DirName(dir)+" arrow";
   return true;
  }
int OwnPositionCount()
  {
   int count=0;
   for(int i=0;i<PositionsTotal();i++)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic) count++;
     }
   return count;
  }
ulong OwnPending()
  {
   for(int i=0;i<OrdersTotal();i++)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol ||
         (ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      int type=(int)OrderGetInteger(ORDER_TYPE);
      if(type==ORDER_TYPE_BUY_STOP || type==ORDER_TYPE_SELL_STOP) return ticket;
     }
   return 0;
  }
void CancelPending(const string reason)
  {
   ulong ticket=OwnPending();
   if(ticket==0) { g_pendingTicket=0; g_pendingExpiry=0; return; }
   MqlTradeRequest request={};
   MqlTradeResult result={};
   request.action=TRADE_ACTION_REMOVE;
   request.order=ticket;
   if(OrderSend(request,result) && result.retcode==TRADE_RETCODE_DONE)
     {
      Event("CANCEL",0,0,reason+" ticket="+IntegerToString((long)ticket));
      g_pendingTicket=0;
      g_pendingExpiry=0;
     }
   else Event("ERROR",0,0,"cancel failed ticket="+IntegerToString((long)ticket)+
              " retcode="+IntegerToString((int)result.retcode));
  }
double SizeForRisk(const int dir,const double entry,const double stop)
  {
   double oneLot=0;
   if(!OrderCalcProfit(dir>0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,
                       _Symbol,1.0,entry,stop,oneLot) || oneLot>=0) return 0;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0 || minLot<=0 || maxLot<=0) return 0;
   // Reserve 10% of the research risk budget for costs and adverse fill.
   double budget=AccountInfoDouble(ACCOUNT_EQUITY)*InpRiskPct/100.0*0.90;
   double lots=MathFloor(budget/(-oneLot)/step+1e-9)*step;
   lots=MathMin(lots,MathFloor(maxLot/step+1e-9)*step);
   lots=NormalizeDouble(lots,8);
   return lots>=minLot?lots:0;
  }
void Place(const int dir,const double high,const double low,
           const datetime signalTime,const double score)
  {
   MqlTick quote;
   if(!SymbolInfoTick(_Symbol,quote))
     { Event("SKIP",dir,score,"no quote"); return; }
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=_Point;
   double spread=quote.ask-quote.bid;
   double entry=dir>0?GridUp(high+spread+tick,tick):
                      GridDown(low-tick,tick);
   double stop=dir>0?GridDown(low-tick,tick):
                     GridUp(high+tick,tick);
   double distance=MathAbs(entry-stop);
   double minDistance=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(distance<=0 || spread<0 ||
      spread/distance>InpMaxSpreadRiskFraction)
     { Event("SKIP",dir,score,"spread/risk="+Num(spread/MathMax(distance,tick))); return; }
   if(dir>0?(entry<=quote.ask+minDistance || stop>=quote.bid-minDistance):
            (entry>=quote.bid-minDistance || stop<=quote.ask+minDistance))
     { Event("SKIP",dir,score,"broker stop distance or price already crossed"); return; }
   double target=dir>0?GridUp(entry+InpTargetR*distance,tick):
                       GridDown(entry-InpTargetR*distance,tick);
   double volume=SizeForRisk(dir,entry,stop);
   if(volume<=0)
     { Event("SKIP",dir,score,"minimum volume exceeds risk budget"); return; }
   datetime expiry=signalTime+PeriodSeconds(PERIOD_M15)*(InpExpiryM15Bars+1);
   int expirationModes=(int)SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE);
   if((expirationModes & SYMBOL_EXPIRATION_SPECIFIED)!=SYMBOL_EXPIRATION_SPECIFIED ||
      expiry<=TimeCurrent())
     { Event("SKIP",dir,score,"broker-side specified expiry unavailable"); return; }
   MqlTradeRequest request={};
   MqlTradeCheckResult check={};
   request.action=TRADE_ACTION_PENDING;
   request.symbol=_Symbol;
   request.magic=InpMagic;
   request.volume=volume;
   request.type=dir>0?ORDER_TYPE_BUY_STOP:ORDER_TYPE_SELL_STOP;
   request.price=entry;
   request.sl=stop;
   request.tp=target;
   request.type_time=ORDER_TIME_SPECIFIED;
   request.expiration=expiry;
   request.type_filling=ORDER_FILLING_RETURN;
   request.comment="TMR:"+IntegerToString((long)signalTime);
   if(!OrderCheck(request,check) ||
      (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE &&
       check.retcode!=TRADE_RETCODE_PLACED))
     {
      Event("SKIP",dir,score,"OrderCheck retcode="+IntegerToString((int)check.retcode)+
            " "+check.comment);
      return;
     }
   MqlTradeResult result={};
   if(!OrderSend(request,result) ||
      (result.retcode!=TRADE_RETCODE_PLACED && result.retcode!=TRADE_RETCODE_DONE))
     {
      Event("SKIP",dir,score,"OrderSend retcode="+IntegerToString((int)result.retcode)+
            " "+result.comment);
      return;
     }
   ulong liveTicket=OwnPending();
   if(liveTicket>0)
     {
      datetime actualExpiry=(datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      if(actualExpiry!=expiry)
        {
         g_pendingTicket=liveTicket;
         CancelPending("broker expiry differs from requested expiry");
         Event("ERROR",dir,score,"pending expiry mismatch");
         return;
        }
      g_pendingTicket=liveTicket;
      g_pendingExpiry=expiry;
     }
   else if(OwnPositionCount()==0)
     {
      Event("ERROR",dir,score,"OrderSend accepted but no pending order or position");
      return;
     }
   Event("ORDER",dir,score,"signal="+TimeToString(signalTime,TIME_DATE|TIME_MINUTES)+
         " entry="+Num(entry,_Digits)+" stop="+Num(stop,_Digits)+
         " target="+Num(target,_Digits)+" lots="+Num(volume,4)+
         " spread="+Num(spread,_Digits)+
         " expiry="+TimeToString(expiry,TIME_DATE|TIME_MINUTES)+
         " retcode="+IntegerToString((int)result.retcode));
  }
int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER))
     { Print("TrenderMarketResearchEA is tester-only"); return INIT_FAILED; }
   if(InpMode<0 || InpMode>1 || InpRiskPct<=0 || InpRiskPct>5 ||
      InpTargetR<=0 || InpExpiryM15Bars<1 || InpMagic==0 ||
      InpMaxSpreadRiskFraction<=0 || InpMaxBandDistanceATR<0)
      return INIT_PARAMETERS_INCORRECT;
   g_file="TrenderMarketResearch_"+InpRunId+".csv";
   int file=FileOpen(g_file,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,';');
   if(file!=INVALID_HANDLE)
     {
      FileWrite(file,"time","symbol","kind","dir","h4_score","detail");
      FileClose(file);
     }
   Event("START",0,0,"mode="+IntegerToString(InpMode)+
         " run="+InpRunId+" risk="+Num(InpRiskPct)+
         " targetR="+Num(InpTargetR));
   // A tester run may start inside an M15 candle; wait for the next close.
   g_lastM15=iTime(_Symbol,PERIOD_M15,0);
   return INIT_SUCCEEDED;
  }
void OnDeinit(const int reason)
  { Event("END",0,0,"reason="+IntegerToString(reason)); }
void OnTick()
  {
   datetime now=TimeCurrent();
   if(g_pendingExpiry>0 && now>=g_pendingExpiry)
      CancelPending("two-bar entry expiry");
   datetime currentM15=iTime(_Symbol,PERIOD_M15,0);
   if(currentM15<=0 || currentM15==g_lastM15) return;
   g_lastM15=currentM15;
   datetime currentH4=iTime(_Symbol,PERIOD_H4,0);
   int scanDir=0;
   double score=0,efficiency=0,moveATR=0;
   string scanWhy="";
   bool scanned=H4Scan(scanDir,score,efficiency,moveATR,scanWhy);
   if(currentH4!=g_lastH4)
     {
      g_lastH4=currentH4;
      Event("SCAN",scanDir,score,"eligible="+(scanned?"1":"0")+
            " ER="+Num(efficiency)+" moveATR="+Num(moveATR)+
            " "+scanWhy);
     }
   if(InpMode==1 && OwnPending()>0 &&
      (!scanned || (g_pendingTicket>0 &&
       ((int)OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_STOP?scanDir<0:scanDir>0))))
      CancelPending("H4 scan invalidated");
   int arrowDir=0;
   double distanceATR=0,signalHigh=0,signalLow=0;
   datetime signalTime=0;
   string arrowWhy="";
   if(!M15Arrow(arrowDir,distanceATR,signalHigh,signalLow,signalTime,arrowWhy))
      return;
   if(distanceATR>InpMaxBandDistanceATR)
     { Event("SKIP",arrowDir,score,"arrow too far from band ATR="+Num(distanceATR)); return; }
   if(InpMode==1 && (!scanned || arrowDir!=scanDir))
     { Event("SKIP",arrowDir,score,"H4 scan not aligned: "+scanWhy); return; }
   if(OwnPositionCount()>0 || OwnPending()>0)
     { Event("SKIP",arrowDir,score,"own position or pending entry exists"); return; }
   Event("SIGNAL",arrowDir,score,"M15="+TimeToString(signalTime,TIME_DATE|TIME_MINUTES)+
         " bandDistanceATR="+Num(distanceATR));
   Place(arrowDir,signalHigh,signalLow,signalTime,score);
  }
