// Minimal tester-only bar exporter for a fast, approximate parameter screen.
#property strict
#property version "1.000"
input string InpRunId="quick_screen";
int g_file=INVALID_HANDLE;
datetime g_lastM1=0,g_lastM3=0,g_lastM5=0,g_lastM15=0;
int g_rows=0;

void WriteClosedBar(const ENUM_TIMEFRAMES tf,datetime &lastOpen)
  {
   datetime opened=iTime(_Symbol,tf,0);
   if(opened<=0 || opened==lastOpen) return;
   lastOpen=opened;
   MqlRates bars[];
   if(CopyRates(_Symbol,tf,1,1,bars)!=1) return;
   FileWrite(g_file,(int)tf,TimeToString(bars[0].time,TIME_DATE|TIME_MINUTES),
             DoubleToString(bars[0].open,_Digits),
             DoubleToString(bars[0].high,_Digits),
             DoubleToString(bars[0].low,_Digits),
             DoubleToString(bars[0].close,_Digits),
             (long)bars[0].tick_volume,bars[0].spread,
             (long)bars[0].real_volume);
   g_rows++;
  }
int OnInit()
  {
   if(!MQLInfoInteger(MQL_TESTER)) return INIT_FAILED;
   g_file=FileOpen("TrenderBars_"+InpRunId+"_"+_Symbol+".csv",
                   FILE_WRITE|FILE_CSV|FILE_COMMON|FILE_ANSI,';');
   if(g_file==INVALID_HANDLE) return INIT_FAILED;
   FileWrite(g_file,"tf","time","open","high","low","close",
             "tick_volume","spread_points","real_volume");
   return INIT_SUCCEEDED;
  }
void OnTick()
  {
   WriteClosedBar(PERIOD_M1,g_lastM1);
   WriteClosedBar(PERIOD_M3,g_lastM3);
   WriteClosedBar(PERIOD_M5,g_lastM5);
   WriteClosedBar(PERIOD_M15,g_lastM15);
  }
void OnDeinit(const int reason)
  {
   if(g_file!=INVALID_HANDLE) { FileFlush(g_file); FileClose(g_file); }
   Print("TrenderBarExport ",_Symbol," rows=",g_rows," reason=",reason);
  }
