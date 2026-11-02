//+------------------------------------------------------------------+
//|                                                     SignalViz.mq5 |
//|  Visual companion for MQL5_Final_Fixed_System.                   |
//|  Draws boxes on the chart exactly where the EA's signal logic     |
//|  would fire: wick-rejection and trend-breakout setups.            |
//+------------------------------------------------------------------+
#property copyright "SignalViz - strategy visualizer"
#property indicator_chart_window
#property indicator_plots   0
#property indicator_buffers 0

input string   _s1                 = "=== Signal params (mirror the EA) ===";
input double   Inp_BodyRatio       = 0.7;    // Min body/range ratio for trend candle
input double   Inp_AtrMultiplier   = 1.5;    // Min signal bar range (x ATR)
input int      Inp_LevelLookback   = 30;     // Support/resistance lookback (bars)
input double   Inp_LevelTolATR     = 0.1;    // Level touch tolerance (x ATR)
input int      Inp_TrendLookback   = 20;     // Trend breakout lookback (bars)
input double   Inp_ExpansionFactor = 1.2;    // ATR expansion factor vs average
input int      Inp_ATRAvgPeriod    = 50;     // ATR average lookback for expansion

input string   _s2                 = "=== HTF filter marking ===";
input bool     Inp_UseHTFFilter    = true;   // Mark signals the H4 EMA200 filter would block
input ENUM_TIMEFRAMES Inp_HTF      = PERIOD_H4;
input int      Inp_HTF_EMA_Period  = 200;

input string   _s3                 = "=== Display ===";
input int      Inp_MaxBars         = 500;    // Max bars to scan back (chart clutter)
input bool     Inp_ShowWick        = true;   // Show wick-rejection signals
input bool     Inp_ShowTrend       = true;   // Show trend-breakout signals
input bool     Inp_ShowFiltered    = false;  // Show HTF-blocked signals (gray *)
input int      Inp_BoxExtend       = 3;      // Bars a box extends right of signal bar
input bool     Inp_DrawLevels      = true;   // Draw the S/R level line
input bool     Inp_DrawMid         = true;   // Draw the retest (midpoint) limit line

int      hATR = INVALID_HANDLE;
int      hEMA = INVALID_HANDLE;
datetime g_lastBar = 0;
int      g_lastTotal = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   hATR = iATR(_Symbol, _Period, 14);
   if(hATR == INVALID_HANDLE)
     {
      Print("SignalViz: failed to create ATR handle");
      return(INIT_FAILED);
     }
   if(Inp_UseHTFFilter)
     {
      hEMA = iMA(_Symbol, Inp_HTF, Inp_HTF_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      if(hEMA == INVALID_HANDLE)
        {
         Print("SignalViz: failed to create HTF EMA handle");
         return(INIT_FAILED);
        }
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "SV_");
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
  }

//+------------------------------------------------------------------+
//| Same rules as the EA's WickScoreAtLevel(), evaluated at bar i     |
//+------------------------------------------------------------------+
int WickScoreAt(const double &hi[], const double &lo[],
                const double &op[], const double &cl[],
                const double &atr[], int i, int limit)
  {
   double h1 = hi[i], l1 = lo[i], o1 = op[i], c1 = cl[i];
   double range = h1 - l1;
   if(range <= 0.0)
      return 0;
   if(i + Inp_LevelLookback + 1 >= limit)
      return 0;

   double sigHigh = hi[i+1], sigLow = lo[i+1];
   for(int k = i+1; k <= i+Inp_LevelLookback; k++)
     {
      if(hi[k] > sigHigh) sigHigh = hi[k];
      if(lo[k] < sigLow)  sigLow  = lo[k];
     }

   double currentATR = atr[i];
   if(currentATR <= 0.0)
      return 0;
   if(range < (Inp_AtrMultiplier * currentATR))
      return 0;

   double uWick = h1 - MathMax(o1, c1);
   double lWick = MathMin(o1, c1) - l1;
   double tol   = Inp_LevelTolATR * currentATR;

   if(lWick/range >= 0.6 && l1 <= sigLow + tol && uWick/range <= 0.1) return 3;
   if(uWick/range >= 0.6 && h1 >= sigHigh - tol && lWick/range <= 0.1) return -3;
   return 0;
  }

//+------------------------------------------------------------------+
//| Same rules as the EA's ImprovedTrendDirection(), at bar i         |
//+------------------------------------------------------------------+
int TrendDirAt(const double &hi[], const double &lo[],
               const double &op[], const double &cl[],
               const double &atr[], int i, int limit)
  {
   double h1 = hi[i], l1 = lo[i], o1 = op[i], c1 = cl[i];
   double range = h1 - l1;
   if(range <= 0.0)
      return 0;
   if(i + MathMax(Inp_TrendLookback, Inp_ATRAvgPeriod) + 1 >= limit)
      return 0;

   double sigHigh = hi[i+1], sigLow = lo[i+1];
   for(int k = i+1; k <= i+Inp_TrendLookback; k++)
     {
      if(hi[k] > sigHigh) sigHigh = hi[k];
      if(lo[k] < sigLow)  sigLow  = lo[k];
     }

   double atrNow = atr[i];
   if(atrNow <= 0.0)
      return 0;
   double sum = 0.0;
   int cnt = 0;
   for(int k = i+1; k <= i+Inp_ATRAvgPeriod; k++)
     {
      if(atr[k] > 0.0) { sum += atr[k]; cnt++; }
     }
   if(cnt < 2)
      return 0;
   double atrAvg = sum / cnt;

   bool expansion  = (atrNow > atrAvg * Inp_ExpansionFactor);
   bool solidBody  = (MathAbs(c1 - o1) / range >= Inp_BodyRatio);

   if(c1 > sigHigh && solidBody && expansion) return 1;
   if(c1 < sigLow  && solidBody && expansion) return -1;
   return 0;
  }

//+------------------------------------------------------------------+
//| Would the HTF EMA200 filter allow this trade?                      |
//+------------------------------------------------------------------+
bool HTFAllows(int i, const double &cl[], bool isBuy, const datetime &tm[])
  {
   if(!Inp_UseHTFFilter || hEMA == INVALID_HANDLE)
      return true;

   int h4shift = iBarShift(_Symbol, Inp_HTF, tm[i], false);
   if(h4shift < 0)
      return true;
   // last CLOSED higher-timeframe bar at signal time = h4shift+1
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hEMA, 0, h4shift + 1, 1, buf) <= 0)
      return true;
   return isBuy ? (cl[i] > buf[0]) : (cl[i] < buf[0]);
  }

//+------------------------------------------------------------------+
bool DrawSignal(int i, int sigType, bool filtered,
                const datetime &tm[], const double &hi[], const double &lo[],
                const double &op[], const double &cl[],
                double atrVal, int digits)
  {
   bool   isBuy = (sigType > 0);
   bool   isWick = (MathAbs(sigType) == 3);
   double sigHigh = hi[i], sigLow = lo[i];
   datetime t1 = tm[i];
   datetime t2 = tm[i] + PeriodSeconds() * Inp_BoxExtend;

   color  col;
   if(filtered)
      col = clrGray;
   else if(isWick)
      col = isBuy ? clrDodgerBlue : clrCrimson;
   else
      col = isBuy ? clrSeaGreen : clrOrangeRed;

   string suffix = IntegerToString(i);
   string tag    = (isWick ? "W-" : "T-") + (isBuy ? "BUY" : "SELL") + (filtered ? " *" : "");

   // --- box around the signal bar ---
   string box = "SV_box_" + suffix;
   bool ok = ObjectCreate(0, box, OBJ_RECTANGLE, 0, t1, sigHigh, t2, sigLow);
   ObjectSetInteger(0, box, OBJPROP_COLOR, col);
   ObjectSetInteger(0, box, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, box, OBJPROP_WIDTH, isWick ? 2 : 1);
   ObjectSetInteger(0, box, OBJPROP_FILL, isWick);
   ObjectSetInteger(0, box, OBJPROP_BACK, false);
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, false);

   // --- label ---
   string lbl = "SV_lbl_" + suffix;
   double lblPrice = isBuy ? sigLow - atrVal * 0.5 : sigHigh + atrVal * 0.5;
   ObjectCreate(0, lbl, OBJ_TEXT, 0, t1, lblPrice);
   ObjectSetString(0, lbl, OBJPROP_TEXT, tag);
   ObjectSetInteger(0, lbl, OBJPROP_COLOR, col);
   ObjectSetInteger(0, lbl, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, lbl, OBJPROP_ANCHOR, isBuy ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetInteger(0, lbl, OBJPROP_SELECTABLE, false);

   if(!Inp_DrawLevels)
      return(ok);

   // --- the S/R level that was tested (dotted) ---
   int lb = Inp_LevelLookback;
   double level = isBuy ? lo[i+1] : hi[i+1];
   double lHi = hi[i+1], lLo = lo[i+1];
   for(int k = i+1; k <= i+lb; k++)
     {
      if(hi[k] > lHi) lHi = hi[k];
      if(lo[k] < lLo) lLo = lo[k];
     }
   level = isBuy ? lLo : lHi;
   string lvl = "SV_lvl_" + suffix;
   ObjectCreate(0, lvl, OBJ_TREND, 0, tm[i+lb], level, t2, level);
   ObjectSetInteger(0, lvl, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, lvl, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, lvl, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, lvl, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, lvl, OBJPROP_SELECTABLE, false);

   // --- the retest limit price the EA orders at (midpoint, dashed) ---
   if(Inp_DrawMid)
     {
      double mid = NormalizeDouble((op[i] + cl[i]) / 2.0, digits);
      string md = "SV_mid_" + suffix;
      ObjectCreate(0, md, OBJ_TREND, 0, t1, mid, t2, mid);
      ObjectSetInteger(0, md, OBJPROP_COLOR, col);
      ObjectSetInteger(0, md, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, md, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, md, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, md, OBJPROP_SELECTABLE, false);
     }
   return(ok);
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < Inp_ATRAvgPeriod + 3)
      return(0);

   // --- force series indexing (0 = current bar) on EVERY array so all
   // --- the i+1 = "one bar older" shift math below is guaranteed right ---
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hATR, 0, 0, rates_total, atr) <= 0)
      return(0);
   int atrLen = ArraySize(atr);
   if(atrLen < Inp_ATRAvgPeriod + 3)
      return(0);
   int limit = MathMin(rates_total, atrLen);

   // --- redraw once for history, then incrementally on each new bar ---
   datetime curBar = time[0];
   if(curBar == g_lastBar && rates_total - g_lastTotal <= 1)
      return(rates_total);
   bool fullRedraw = (g_lastBar == 0) || (rates_total - g_lastTotal > 1);
   g_lastBar    = curBar;
   g_lastTotal  = rates_total;

   if(fullRedraw)
      ObjectsDeleteAll(0, "SV_");

   // series indexing: "last N closed bars" = indices 1..N (0 = forming)
   int start = (fullRedraw ? Inp_MaxBars : 50);
   int maxStart = limit - Inp_ATRAvgPeriod - 2;
   if(start > maxStart)
      start = maxStart;
   int end = 1;                    // never evaluate the forming bar
   if(start < end)
      return(rates_total);

   int digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int scanned   = 0, nWick = 0, nTrend = 0, nFiltered = 0, nDrawn = 0;

   for(int i = start; i >= end; i--)
     {
      scanned++;
      int wick = WickScoreAt(high, low, open, close, atr, i, limit);
      int sig  = wick;
      if(sig != 0)
         nWick++;
      else
        {
         sig = TrendDirAt(high, low, open, close, atr, i, limit);
         if(sig != 0)
            nTrend++;
        }
      if(sig == 0)
         continue;
      bool isWick = (MathAbs(sig) == 3);
      if(isWick && !Inp_ShowWick)
         continue;
      if(!isWick && !Inp_ShowTrend)
         continue;

      bool isBuy    = (sig > 0);
      bool filtered = !HTFAllows(i, close, isBuy, time);
      if(filtered)
         nFiltered++;
      if(filtered && !Inp_ShowFiltered)
         continue;
      if(DrawSignal(i, sig, filtered, time, high, low, open, close, atr[i], digits))
         nDrawn++;
     }

   if(fullRedraw)
      Print("SignalViz: fullRedraw scanned=", scanned,
            " wick=", nWick, " trend=", nTrend,
            " htfFiltered=", nFiltered, " boxesDrawn=", nDrawn);

   return(rates_total);
  }
//+------------------------------------------------------------------+
