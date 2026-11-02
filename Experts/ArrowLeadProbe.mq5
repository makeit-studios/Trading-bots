// Research-only probe: observe M5 and M15 Simple Trender arrows on the same ticks.
// It never sends orders. Event timestamps are the first observed tick, not bar time.
#property strict
#property version "1.00"

#define HISTORY_BARS 600
#define EMA_LOW_LENGTH 26
#define VWAP_EMA_LENGTH 13

struct TfState
  {
   ENUM_TIMEFRAMES tf;
   datetime barTime;
   double emaLow,smoothedVwap,previousClose,sumPV,sumVolume;
   int sessionDay,lastClosedBand,lastClosedVwapSide;
   bool seenUp,seenDown;
   int lastLive;
  };

TfState g_m5,g_m15;
bool g_ready=false;

string Side(const int dir) { return dir>0?"UP":dir<0?"DOWN":"NONE"; }
string Stamp(const datetime value) { return TimeToString(value,TIME_DATE|TIME_SECONDS); }
int SessionDay(const datetime value)
  {
   MqlDateTime parts;
   TimeToStruct(value,parts);
   return parts.year*10000+parts.mon*100+parts.day;
  }
int Arrow(const double close,const double priorClose,const double emaLow,const double smooth)
  {
   if(close>emaLow && priorClose<smooth && close>smooth) return 1;
   if(close<emaLow && priorClose>smooth && close<smooth) return -1;
   return 0;
  }
int Direction(const double value,const double level)
  { return value>level?1:value<level?-1:0; }

// CopyRates places the oldest copied candle at physical index zero.
// Recompute only at bar boundaries; exclude the still forming last candle.
bool SeedClosedBars(TfState &state,int &closedArrow,datetime &closedBar)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int n=CopyRates(_Symbol,state.tf,0,HISTORY_BARS,rates);
   if(n<205) return false;
   double ema=0,smooth=0,sumPV=0,sumVolume=0;
   double alphaEma=2.0/(EMA_LOW_LENGTH+1.0);
   double alphaVwap=2.0/(VWAP_EMA_LENGTH+1.0);
   int day=0;
   closedArrow=0;
   closedBar=rates[n-2].time;
   for(int i=0;i<n-1;i++)
     {
      int currentDay=SessionDay(rates[i].time);
      if(currentDay!=day) { sumPV=0; sumVolume=0; day=currentDay; }
      double volume=MathMax(1.0,(double)rates[i].tick_volume);
      double typical=(rates[i].high+rates[i].low+rates[i].close)/3.0;
      sumPV+=typical*volume;
      sumVolume+=volume;
      double vwap=sumPV/sumVolume;
      ema=i==0?rates[i].low:alphaEma*rates[i].low+(1.0-alphaEma)*ema;
      smooth=i==0?vwap:alphaVwap*vwap+(1.0-alphaVwap)*smooth;
      if(i==n-2 && i>0)
         closedArrow=Arrow(rates[i].close,rates[i-1].close,ema,smooth);
     }
   state.emaLow=ema;
   state.smoothedVwap=smooth;
   state.previousClose=rates[n-2].close;
   state.sumPV=sumPV;
   state.sumVolume=sumVolume;
   state.sessionDay=day;
   state.lastClosedBand=Direction(state.previousClose,ema);
   state.lastClosedVwapSide=Direction(state.previousClose,smooth);
   state.barTime=rates[n-1].time;
   return true;
  }

int LiveArrow(const TfState &state,MqlRates &bar)
  {
   MqlRates current[];
   if(CopyRates(_Symbol,state.tf,0,1,current)!=1) return 0;
   bar=current[0];
   double volume=MathMax(1.0,(double)bar.tick_volume);
   double pv=SessionDay(bar.time)==state.sessionDay?state.sumPV:0;
   double total=SessionDay(bar.time)==state.sessionDay?state.sumVolume:0;
   double typical=(bar.high+bar.low+bar.close)/3.0;
   double vwap=(pv+typical*volume)/(total+volume);
   double ema=2.0/(EMA_LOW_LENGTH+1.0)*bar.low+
              (1.0-2.0/(EMA_LOW_LENGTH+1.0))*state.emaLow;
   double smooth=2.0/(VWAP_EMA_LENGTH+1.0)*vwap+
                 (1.0-2.0/(VWAP_EMA_LENGTH+1.0))*state.smoothedVwap;
   return Arrow(bar.close,state.previousClose,ema,smooth);
  }

void Record(const string kind,const TfState &state,const int dir,const string extra="")
  {
   Print("ALP|",kind,"|",Stamp(TimeCurrent()),"|",Stamp(state.barTime),
         "|",Side(dir),"|",extra);
  }

void RefreshBar(TfState &state)
  {
   datetime latest=iTime(_Symbol,state.tf,0);
   if(latest==0 || latest==state.barTime) return;
   bool hadUp=state.seenUp,hadDown=state.seenDown;
   datetime previous=state.barTime;
   int closed=0;
   datetime closedBar=0;
   if(!SeedClosedBars(state,closed,closedBar)) return;
   string label=state.tf==PERIOD_M5?"M5":"M15";
   if(previous>0)
     {
      if((label=="M5" && (hadUp || hadDown || closed!=0)) ||
         (label=="M15" && (hadUp || hadDown || closed!=0)))
         Record(label+"_CLOSE",state,closed,
                "closed_bar="+Stamp(closedBar)+
                ";seen_up="+(hadUp?"1":"0")+
                ";seen_down="+(hadDown?"1":"0"));
     }
   state.seenUp=false;
   state.seenDown=false;
   state.lastLive=0;
  }

void Observe(TfState &state)
  {
   MqlRates bar;
   int live=LiveArrow(state,bar);
   string label=state.tf==PERIOD_M5?"M5":"M15";
   if(live!=0 && ((live>0 && !state.seenUp) || (live<0 && !state.seenDown)))
     {
      if(live>0) state.seenUp=true;
      else state.seenDown=true;
      string extra="price="+DoubleToString(bar.close,_Digits);
      if(state.tf==PERIOD_M5)
         extra+=";m15_band="+Side(g_m15.lastClosedBand)+
                ";m15_vwap="+Side(g_m15.lastClosedVwapSide);
      Record(label+"_FIRST",state,live,extra);
     }
   if(state.lastLive!=0 && live==0)
      Record(label+"_OFF",state,state.lastLive,"");
   state.lastLive=live;
  }

int OnInit()
  {
   g_m5.tf=PERIOD_M5;
   g_m15.tf=PERIOD_M15;
   int closed=0;
   datetime bar=0;
   if(!SeedClosedBars(g_m15,closed,bar) || !SeedClosedBars(g_m5,closed,bar))
      return INIT_FAILED;
   // A visible arrow at attachment is not a newly observed first-sight event.
   MqlRates live;
   int m15=LiveArrow(g_m15,live);
   g_m15.seenUp=m15>0; g_m15.seenDown=m15<0; g_m15.lastLive=m15;
   int m5=LiveArrow(g_m5,live);
   g_m5.seenUp=m5>0; g_m5.seenDown=m5<0; g_m5.lastLive=m5;
   g_ready=true;
   Print("ALP|START|",Stamp(TimeCurrent()),"|symbol=",_Symbol,
         ";M5=",Stamp(g_m5.barTime),";M15=",Stamp(g_m15.barTime));
   return INIT_SUCCEEDED;
  }
void OnTick()
  {
   if(!g_ready) return;
   RefreshBar(g_m15);
   RefreshBar(g_m5);
   Observe(g_m15);
   Observe(g_m5);
  }
void OnDeinit(const int reason)
  { Print("ALP|END|",Stamp(TimeCurrent()),"|reason=",reason); }
