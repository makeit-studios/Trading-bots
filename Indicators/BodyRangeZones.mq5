#property copyright "Local research prototype"
#property version   "1.02"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3
#property indicator_type1   DRAW_NONE
#property indicator_label1  "Zone upper"
#property indicator_type2   DRAW_NONE
#property indicator_label2  "Zone lower"
#property indicator_type3   DRAW_NONE
#property indicator_label3  "Zone state"

// Boxes use candle bodies only. All decisions use completed candles.
// Sync-BodyRangeZones.ps1 mirrors this source and its compiled EX5 to MT5.
// Buffer 0 = upper boundary, 1 = lower boundary, 2 = active state.
// Only the latest closed bar contains a value, and only when its active
// zone is among the newest retained Market Watch boxes.

input int      InpMinBars              = 3;    // earliest low-high-low / high-low-high
input int      InpMaxBars              = 12;   // longest formation window
input int      InpBodyLookback         = 14;
input double   InpMaxWidthBodies       = 3.5;
input double   InpMinWidthBodies       = 0.8;
input double   InpEdgeBandFraction     = 0.28;
input int      InpMaxRetainedBoxes     = 5;   // set to 3 for a smaller watch list
input int      InpSecondsPerSymbol     = 3;
input string   InpInstanceTag          = "default";

double UpperBuffer[];
double LowerBuffer[];
double StateBuffer[];

struct RangeZone
  {
   int       first;
   int       identified;
   int       last;
   double    upper;
   double    lower;
   bool      active;
  };

struct ScanHit
  {
   string          symbol;
   ENUM_TIMEFRAMES timeframe;
   datetime        first;
   datetime        identified;
   datetime        last;
   datetime        evaluated_bar;
   double          upper;
   double          lower;
  };

ScanHit  MarketHits[];
ScanHit  ActiveCandidates[];
int      MarketCursor = 0;
int      MarketCount = 0;
int      ScannedCount = 0;
int      UnavailableCount = 0;
datetime LastChartClosedBar = 0;
int      LastChartBars = 0;
string   ObjectPrefix;

double BodyHigh(const MqlRates &bar)
  {
   return MathMax(bar.open,bar.close);
  }

double BodyLow(const MqlRates &bar)
  {
   return MathMin(bar.open,bar.close);
  }

// Three alternating body-close edge touches reveal the first incomplete
// W or M. The third touch is known when that candle closes, before a full
// second bounce or a long sideways run is required.
bool IncompleteSwing(const MqlRates &rates[],const int first,const int last,
                     const double upper,const double lower)
  {
   double height = upper-lower;
   double lower_band = lower+height*InpEdgeBandFraction;
   double upper_band = upper-height*InpEdgeBandFraction;
   int first_edge = 0;
   int previous_edge = 0;
   int alternations = 0;
   for(int i=first;i<=last;i++)
     {
      int edge = 0;
      if(rates[i].close <= lower_band) edge = -1;
      else if(rates[i].close >= upper_band) edge = 1;
      if(edge == 0) continue;
      if(first_edge == 0) first_edge = edge;
      if(previous_edge != 0 && edge != previous_edge) alternations++;
      previous_edge = edge;
     }
   return alternations >= 2 && previous_edge == first_edge;
  }

bool InitialWindow(const MqlRates &rates[],const int first,const int last,
                   double &upper,double &lower)
  {
   upper = -DBL_MAX;
   lower = DBL_MAX;
   for(int i=first;i<=last;i++)
     {
      upper = MathMax(upper,BodyHigh(rates[i]));
      lower = MathMin(lower,BodyLow(rates[i]));
     }
   double width = upper-lower;
   if(width <= 0.0) return false;
   double average_body = 0.0;
   for(int i=first-InpBodyLookback;i<first;i++)
      average_body += MathAbs(rates[i].close-rates[i].open);
   average_body /= InpBodyLookback;
   if(average_body <= 0.0 || width > average_body*InpMaxWidthBodies ||
      width < average_body*InpMinWidthBodies) return false;
   return IncompleteSwing(rates,first,last,upper,lower);
  }

void AddZone(RangeZone &zones[],const RangeZone &zone)
  {
   int size = ArraySize(zones);
   ArrayResize(zones,size+1,256);
   zones[size] = zone;
  }

// CopyRates stores the oldest candle at index 0 in physical memory.
void FindZones(const MqlRates &rates[],const int count,RangeZone &zones[],
               double &upper_series[],double &lower_series[],double &state_series[])
  {
   ArrayResize(zones,0);
   ArrayResize(upper_series,count);
   ArrayResize(lower_series,count);
   ArrayResize(state_series,count);
   ArrayInitialize(upper_series,EMPTY_VALUE);
   ArrayInitialize(lower_series,EMPTY_VALUE);
   ArrayInitialize(state_series,0.0);
   if(count < InpBodyLookback+InpMinBars+1) return;

   bool in_zone = false;
   RangeZone zone;
   ZeroMemory(zone);
   int closed_count = count-1; // final element is the forming bar
   for(int i=InpBodyLookback+InpMinBars-1;i<closed_count;i++)
     {
      if(!in_zone)
        {
         double upper = 0.0,lower = 0.0;
         int first = -1;
         for(int length=InpMinBars;length<=InpMaxBars;length++)
           {
            int candidate_first = i-length+1;
            if(candidate_first < InpBodyLookback) break;
            if(InitialWindow(rates,candidate_first,i,upper,lower))
              {
               first = candidate_first;
               break;
              }
           }
         if(first < 0) continue;
         zone.first = first;
         zone.identified = i;
         zone.last = i;
         zone.upper = upper;
         zone.lower = lower;
         zone.active = true;
         in_zone = true;
         upper_series[i] = upper;
         lower_series[i] = lower;
         state_series[i] = 1.0;
         continue;
        }

      // Wicks may cross the box. Only a completed close beyond a fixed
      // body edge invalidates it; a close back inside keeps it active.
      if(rates[i].close > zone.upper || rates[i].close < zone.lower)
        {
         zone.active = false;
         in_zone = false;
         continue;
        }
      zone.last = i;
      upper_series[i] = zone.upper;
      lower_series[i] = zone.lower;
      state_series[i] = 1.0;
     }
   if(in_zone) AddZone(zones,zone);
  }

void DrawChartZones()
  {
   ObjectsDeleteAll(0,ObjectPrefix);
   datetime chart_end = iTime(_Symbol,_Period,0)+PeriodSeconds(_Period);
   for(int i=0;i<ArraySize(MarketHits);i++)
     {
      if(MarketHits[i].symbol != _Symbol || MarketHits[i].timeframe != _Period)
         continue;
      string name = ObjectPrefix+IntegerToString(i);
      if(!ObjectCreate(0,name,OBJ_RECTANGLE,0,MarketHits[i].first,
                       MarketHits[i].upper,chart_end,MarketHits[i].lower)) continue;
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrRoyalBlue);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,name,OBJPROP_FILL,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,true);
      ObjectSetString(0,name,OBJPROP_TOOLTIP,
                      StringFormat("Active body range | early W/M seen %s | %s",
                                   TimeToString(MarketHits[i].identified),
                                   EnumToString(_Period)));
      string marker = name+"_identified";
      if(ObjectCreate(0,marker,OBJ_TREND,0,
                      MarketHits[i].identified,MarketHits[i].upper,
                      MarketHits[i].identified,MarketHits[i].lower))
        {
         ObjectSetInteger(0,marker,OBJPROP_COLOR,clrRoyalBlue);
         ObjectSetInteger(0,marker,OBJPROP_STYLE,STYLE_DOT);
         ObjectSetInteger(0,marker,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,marker,OBJPROP_RAY_LEFT,false);
         ObjectSetInteger(0,marker,OBJPROP_RAY_RIGHT,false);
         ObjectSetInteger(0,marker,OBJPROP_BACK,true);
         ObjectSetInteger(0,marker,OBJPROP_SELECTABLE,false);
         ObjectSetString(0,marker,OBJPROP_TOOLTIP,"Early W/M identified on this closed candle");
        }
     }
   ChartRedraw(0);
  }

void RebuildMarketHits()
  {
   ArrayResize(MarketHits,0);
   for(int i=0;i<ArraySize(ActiveCandidates);i++)
     {
      int insert_at = 0;
      while(insert_at<ArraySize(MarketHits) &&
            MarketHits[insert_at].identified >= ActiveCandidates[i].identified)
         insert_at++;
      if(insert_at >= InpMaxRetainedBoxes) continue;
      int size = ArraySize(MarketHits);
      ArrayResize(MarketHits,MathMin(size+1,InpMaxRetainedBoxes));
      for(int j=ArraySize(MarketHits)-1;j>insert_at;j--)
         MarketHits[j] = MarketHits[j-1];
      MarketHits[insert_at] = ActiveCandidates[i];
     }
  }

void RemoveSymbolHit(const string symbol)
  {
   for(int i=ArraySize(ActiveCandidates)-1;i>=0;i--)
      if(ActiveCandidates[i].symbol == symbol)
         ArrayRemove(ActiveCandidates,i,1);
   RebuildMarketHits();
  }

void UpdateMarketHit(const string symbol,const ENUM_TIMEFRAMES timeframe,
                     const MqlRates &rates[],const RangeZone &zones[])
  {
   RemoveSymbolHit(symbol);
   for(int i=0;i<ArraySize(zones);i++)
     {
      if(!zones[i].active) continue;
      int size = ArraySize(ActiveCandidates);
      ArrayResize(ActiveCandidates,size+1);
      ActiveCandidates[size].symbol = symbol;
      ActiveCandidates[size].timeframe = timeframe;
      ActiveCandidates[size].first = rates[zones[i].first].time;
      ActiveCandidates[size].identified = rates[zones[i].identified].time;
      ActiveCandidates[size].last = rates[zones[i].last].time+PeriodSeconds(timeframe);
      ActiveCandidates[size].evaluated_bar = rates[ArraySize(rates)-2].time;
      ActiveCandidates[size].upper = zones[i].upper;
      ActiveCandidates[size].lower = zones[i].lower;
     }
   RebuildMarketHits();
  }

void PruneStaleCandidates()
  {
   bool changed = false;
   for(int i=ArraySize(ActiveCandidates)-1;i>=0;i--)
     {
      string symbol = ActiveCandidates[i].symbol;
      if(!SymbolInfoInteger(symbol,SYMBOL_SELECT) ||
         iTime(symbol,_Period,1) != ActiveCandidates[i].evaluated_bar)
        {
         ArrayRemove(ActiveCandidates,i,1);
         changed = true;
        }
     }
   if(changed) RebuildMarketHits();
  }

bool ScanTimeframe(const string symbol,const ENUM_TIMEFRAMES timeframe)
  {
   int bars = Bars(symbol,timeframe);
   if(bars <= InpBodyLookback+InpMinBars)
     {
      RemoveSymbolHit(symbol);
      return false;
     }
   MqlRates rates[];
   int copied = CopyRates(symbol,timeframe,0,bars,rates);
   if(copied <= InpBodyLookback+InpMinBars)
     {
      RemoveSymbolHit(symbol);
      return false;
     }
   RangeZone zones[];
   double upper[],lower[],state[];
   FindZones(rates,copied,zones,upper,lower,state);
   UpdateMarketHit(symbol,timeframe,rates,zones);
   return true;
  }

void SaveMarketSnapshot()
  {
   int handle = FileOpen("BodyRangeZones_MarketWatch.csv",
                         FILE_WRITE|FILE_CSV|FILE_ANSI,',');
   if(handle == INVALID_HANDLE)
     {
      Print("BodyRangeZones: could not save Market Watch scan, error ",GetLastError());
      return;
     }
   FileWrite(handle,"symbol","timeframe","first_bar","identified_bar",
             "last_bar_end","body_upper","body_lower","status");
   for(int i=0;i<ArraySize(MarketHits);i++)
     {
      FileWrite(handle,MarketHits[i].symbol,EnumToString(MarketHits[i].timeframe),
                TimeToString(MarketHits[i].first,TIME_DATE|TIME_MINUTES),
                TimeToString(MarketHits[i].identified,TIME_DATE|TIME_MINUTES),
                TimeToString(MarketHits[i].last,TIME_DATE|TIME_MINUTES),
                DoubleToString(MarketHits[i].upper,8),
                DoubleToString(MarketHits[i].lower,8),"active");
     }
   FileClose(handle);

   string summary = StringFormat("Active %s body ranges: %d/%d kept | %d/%d Market Watch symbols scanned | %d unavailable\n",
                                 EnumToString(_Period),ArraySize(MarketHits),
                                 InpMaxRetainedBoxes,ScannedCount,MarketCount,UnavailableCount);
   for(int i=0;i<ArraySize(MarketHits);i++)
     {
      int digits = (int)SymbolInfoInteger(MarketHits[i].symbol,SYMBOL_DIGITS);
      summary += StringFormat("%s  %s - %s\n",MarketHits[i].symbol,
                              DoubleToString(MarketHits[i].lower,digits),
                              DoubleToString(MarketHits[i].upper,digits));
     }
   summary += "Current list: MQL5/Files/BodyRangeZones_MarketWatch.csv";
   Comment(summary);
  }

void UpdateChartBuffers()
  {
   ArrayInitialize(UpperBuffer,EMPTY_VALUE);
   ArrayInitialize(LowerBuffer,EMPTY_VALUE);
   ArrayInitialize(StateBuffer,0.0);
   int closed = ArraySize(UpperBuffer)-2;
   if(closed < 0) return;
   for(int i=0;i<ArraySize(MarketHits);i++)
      if(MarketHits[i].symbol == _Symbol && MarketHits[i].timeframe == _Period)
        {
         UpperBuffer[closed] = MarketHits[i].upper;
         LowerBuffer[closed] = MarketHits[i].lower;
         StateBuffer[closed] = 1.0;
         return;
        }
  }

int OnInit()
  {
   if(InpMinBars < 3 || InpMaxBars < InpMinBars || InpBodyLookback < 1 ||
      InpMinWidthBodies <= 0 || InpMaxWidthBodies <= InpMinWidthBodies ||
      InpEdgeBandFraction <= 0 || InpEdgeBandFraction >= 0.5 ||
      InpSecondsPerSymbol < 1 ||
      InpMaxRetainedBoxes < 1 || InpMaxRetainedBoxes > 5)
      return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,UpperBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,LowerBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,StateBuffer,INDICATOR_DATA);
   for(int i=0;i<3;i++) PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"Active Body Range Zones");
   ObjectPrefix = "BRZ_"+InpInstanceTag+"_"+_Symbol+"_"+EnumToString(_Period)+"_";
   ObjectsDeleteAll(0,ObjectPrefix);
   ArrayResize(MarketHits,0);
   ArrayResize(ActiveCandidates,0);
   SaveMarketSnapshot();
   EventSetTimer(InpSecondsPerSymbol);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0,ObjectPrefix);
   Comment("");
   FileDelete("BodyRangeZones_MarketWatch.csv");
  }

void OnTimer()
  {
   if(MarketCursor == 0)
     {
      MarketCount = SymbolsTotal(true);
      ScannedCount = 0;
      UnavailableCount = 0;
     }
   PruneStaleCandidates();
   if(MarketCursor >= MarketCount)
     {
      UpdateChartBuffers();
      DrawChartZones();
      SaveMarketSnapshot();
      MarketCursor = 0;
      return;
     }
   string symbol = SymbolName(MarketCursor,true);
   MarketCursor++;
   bool available = ScanTimeframe(symbol,_Period);
   if(available) ScannedCount++;
   else UnavailableCount++;
   UpdateChartBuffers();
   DrawChartZones();
   SaveMarketSnapshot();
  }

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],const long &tick_volume[],
                const long &volume[],const int &spread[])
  {
   datetime closed_bar = iTime(_Symbol,_Period,1);
   if(prev_calculated == rates_total && closed_bar == LastChartClosedBar &&
      rates_total == LastChartBars) return rates_total;
   MqlRates rates[];
   int copied = CopyRates(_Symbol,_Period,0,rates_total,rates);
   if(copied <= InpBodyLookback+InpMinBars)
     {
      RemoveSymbolHit(_Symbol);
      UpdateChartBuffers();
      DrawChartZones();
      SaveMarketSnapshot();
      return prev_calculated;
     }
   RangeZone zones[];
   double upper[],lower[],state[];
   FindZones(rates,copied,zones,upper,lower,state);
   if(SymbolInfoInteger(_Symbol,SYMBOL_SELECT))
      UpdateMarketHit(_Symbol,_Period,rates,zones);
   else
      RemoveSymbolHit(_Symbol);
   UpdateChartBuffers();
   DrawChartZones();
   SaveMarketSnapshot();
   LastChartClosedBar = closed_bar;
   LastChartBars = rates_total;
   return rates_total;
  }
