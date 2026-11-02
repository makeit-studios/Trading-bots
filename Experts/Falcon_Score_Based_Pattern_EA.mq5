//+------------------------------------------------------------------+
//|                          FalconArcRangeEA_Pro.mq5                |
//| Clean score-based Falcon strategy (MT5)                          |
//+------------------------------------------------------------------+
#property copyright "Falcon Strategy"
#property link      "https://www.mql5.com"
#property version   "2.50"
#property strict

#include <Trade/Trade.mqh>

//--- Trend classification used by score and reversal filter.
enum ENUM_TREND_STATE
  {
   TREND_UP=0,
   TREND_DOWN=1,
   TREND_SIDEWAYS=2
  };

//--- Strategy inputs (editable in MT5 Strategy Tester).
//--- Consolidated: only strategic knobs stay editable. Implementation
//--- details are fixed as #define constants below to limit overfitting.
input string Inp_Expert_Title              ="Falcon_Pro_EA";
input int    Inp_MagicNumber               =12003;

//--- Score model (0..5).
input int    Inp_MinScoreToTrade           =5;

//--- Risk and sizing.
input double Inp_RiskPercent               =1.0;
input bool   Inp_AllowMinLotFloor          =false; // floor to min lot instead of skipping (small accounts)

//--- Indicator and structure settings.
input int    Inp_ATR_Period                =14;
input int    Inp_TrendLookback             =120;

//--- Trade management.
input double Inp_PotentialRR               =2.0;
input double Inp_MinRR                     =1.0;    // Skip trade if reward:risk below this (0 = off)
input bool   Inp_HoldUntilClearReversal    =true;

//+------------------------------------------------------------------+
//| FIXED STRATEGY CONSTANTS (not tunable - limits overfitting)      |
//+------------------------------------------------------------------+
// --- Risk and sizing ---
#define MIN_RISK_DOLLARS              0.10   // keep risk model usable for very small balances
#define MIN_FREE_MARGIN_PERCENT      25.0    // keep this percent of equity free after opening

// --- Indicator and structure ---
#define SWING_LOOKBACK_BARS          10
#define SL_BUFFER_POINTS             25.0

// --- Trigger quality ---
#define ARC_LOOKBACK                 10
#define ARC_TOLERANCE_PTS            15.0
#define RETEST_LOOKBACK_FAR          100      // far-history scan for repeated levels
#define MIN_RETESTS_FOR_LEVEL        3        // minimum touches for a significant level
#define MOMENTUM_BODY_MIN_RATIO      0.60
#define MIN_WICK_RATIO               0.35

// --- Trade management ---
#define MIN_SL_ATR_MULT              1.0
#define MAX_SL_ATR_MULT              2.5
#define TAKE_PROFIT_CAPTURE_PERCENT  90.0
#define TRAIL_ATR_MULT               1.1

// --- Scale-in behaviour ---
#define ENABLE_SCALE_IN              true
#define SCALE_IN_FACTOR              0.50
#define MAX_SCALE_IN_ADDS            1
#define SCALE_IN_TRIGGER_TO_TP       0.35

// --- Execution gates ---
#define TRADE_ON_NEW_BAR_ONLY        true
#define DEBUG_LOGS                   true

//--- Runtime state.
CTrade   ExtTrade;
int      atrHandle=INVALID_HANDLE;
double   atrBuffer[];
datetime lastBarTime=0;
int      g_scaleInAddsBuy=0;
int      g_scaleInAddsSell=0;

void Log(const string msg)
  {
   if(DEBUG_LOGS)
      Print("[",Inp_Expert_Title,"] ",msg);
  }

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

double GetATR(const int index)
  {
   if(atrHandle==INVALID_HANDLE)
      return(0.0);
   if(CopyBuffer(atrHandle,0,index,1,atrBuffer)<1)
      return(0.0);
   return(atrBuffer[0]);
  }

int CountOurPositions()
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol && PositionGetInteger(POSITION_MAGIC)==Inp_MagicNumber)
         count++;
     }
   return(count);
  }

ENUM_TREND_STATE GetMarketStructureTrend(const int lookbackBars)
  {
   double high1=0.0, high2=0.0, low1=0.0, low2=0.0;
   int foundH=0, foundL=0;

   int maxBars=MathMin(lookbackBars,Bars(_Symbol,_Period)-2);
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
   double impulse=MathAbs(iClose(_Symbol,_Period,8)-iClose(_Symbol,_Period,26));
   int hiIdx=iHighest(_Symbol,_Period,MODE_HIGH,8,1);
   int loIdx=iLowest(_Symbol,_Period,MODE_LOW,8,1);
   if(hiIdx<0 || loIdx<0 || impulse<=0.0)
      return(false);
   double correction=iHigh(_Symbol,_Period,hiIdx)-iLow(_Symbol,_Period,loIdx);
   return(correction<impulse*0.40);
  }

bool IsWedgeReversal()
  {
   double wide=iHigh(_Symbol,_Period,12)-iLow(_Symbol,_Period,12);
   double tight=iHigh(_Symbol,_Period,1)-iLow(_Symbol,_Period,1);
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

// Count how many times price has retested a candidate level in a given [startShift..endShift] range.
// We use candle lows for BUY-side support retests and candle highs for SELL-side resistance retests.
int CountRetestsNearLevel(const bool buy,const double level,const int startShift,const int endShift,const double tolerance)
  {
   int touches=0;
   for(int i=startShift;i<=endShift;i++)
     {
      double probe=buy ? iLow(_Symbol,_Period,i) : iHigh(_Symbol,_Period,i);
      if(MathAbs(probe-level)<=tolerance)
         touches++;
     }
   return(touches);
  }

// Find a "strong retest line" in far history.
// BUY: finds repeated highs above current entry (possible upside retest/target line).
// SELL: finds repeated lows below current entry (possible downside retest/target line).
// Returns true when a level with enough retests is found.
bool FindStrongRetestLine(const bool buy,const double entry,double &levelOut,int &touchesOut)
  {
   int bars=Bars(_Symbol,_Period);
   if(bars<20)
      return(false);

   int lookback=MathMax(ARC_LOOKBACK,RETEST_LOOKBACK_FAR);
   int endShift=MathMin(lookback,bars-2);
   if(endShift<5)
      return(false);

   double tolerance=ARC_TOLERANCE_PTS*_Point;
   if(tolerance<=0.0)
      return(false);

   double bestLevel=0.0;
   int bestTouches=0;
   double bestDist=0.0;
   bool found=false;

   // Among levels with enough touches, prefer the NEAREST one to entry:
   // proximity beats an all-time most-touched level far back in a different regime.
   for(int i=3;i<=endShift;i++)
     {
      double candidate=buy ? iHigh(_Symbol,_Period,i) : iLow(_Symbol,_Period,i);

      // For TP purposes we only accept levels on the profitable side of entry.
      if((buy && candidate<=entry) || (!buy && candidate>=entry))
         continue;

      int touches=CountRetestsNearLevel(buy,candidate,3,endShift,tolerance);
      if(touches<MIN_RETESTS_FOR_LEVEL)
         continue;

      double dist=MathAbs(candidate-entry);
      if(!found || dist<bestDist)
        {
         found=true;
         bestTouches=touches;
         bestLevel=candidate;
         bestDist=dist;
        }
     }

   if(!found)
      return(false);

   levelOut=bestLevel;
   touchesOut=bestTouches;
   return(true);
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
   double low1=iLow(_Symbol,_Period,1), low2=iLow(_Symbol,_Period,2), close1=iClose(_Symbol,_Period,1);
   if(buy)
      return(low1<low2 && close1>low2);

   double high1=iHigh(_Symbol,_Period,1), high2=iHigh(_Symbol,_Period,2);
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

// Score map (0..5): trend + trigger + pattern + sweep + wick.
int CalculateScore5(const bool buy,const ENUM_TREND_STATE trend)
  {
   int score=0;
   if((buy && trend!=TREND_DOWN) || (!buy && trend!=TREND_UP)) score++;
   if(IsArcTrigger(buy) || IsMomentumTrigger(buy)) score++;
   if(IsFlagPattern() || IsWedgeReversal()) score++;
   if(HasLiquiditySweep(buy)) score++;
   if(HasWickRejection(buy)) score++;
   return(score);
  }

double NormalizeVolumeToStep(const double lots)
  {
   double volMax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(volStep<=0.0)
      return(0.0);

   double v=MathFloor(lots/volStep)*volStep;
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

   // For micro accounts (e.g., ~10 USD), pure percent risk can become too small to trade.
   // We keep the normal percent model but enforce a tiny minimum risk budget.
   double riskMoney=AccountInfoDouble(ACCOUNT_EQUITY)*(Inp_RiskPercent/100.0);
   riskMoney=MathMax(riskMoney,MIN_RISK_DOLLARS);
   double lossPerLot=(slDistPrice/tickSize)*tickValue;
   if(lossPerLot<=0.0)
      return(0.0);

   return(NormalizeVolumeToStep(riskMoney/lossPerLot));
  }

// Calculates the maximum tradable volume while respecting free-margin safety.
// This function naturally benefits from higher leverage (200..2000):
// higher leverage -> lower margin per lot -> larger affordable position size.
double CalcVolumeByMarginLimit(const bool buy,const double targetVolume)
  {
   double safeTarget=NormalizeVolumeToStep(targetVolume);
   if(safeTarget<=0.0)
      return(0.0);

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double minFreeMargin=equity*MathMax(0.0,MathMin(95.0,MIN_FREE_MARGIN_PERCENT))/100.0;

   // If free margin is already very low, block new positions.
   if(freeMargin<=minFreeMargin)
      return(0.0);

   double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(price<=0.0)
      return(0.0);

   // Estimate required margin for requested size.
   ENUM_ORDER_TYPE orderType=buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double marginNeeded=0.0;
   if(!OrderCalcMargin(orderType,_Symbol,safeTarget,price,marginNeeded) || marginNeeded<=0.0)
      return(0.0);

   double allowedMargin=freeMargin-minFreeMargin;
   if(allowedMargin<=0.0)
      return(0.0);

   // If requested volume already fits, accept it.
   if(marginNeeded<=allowedMargin)
      return(safeTarget);

   // Otherwise scale down proportionally and normalize to broker step.
   double scaled=safeTarget*(allowedMargin/marginNeeded);
   return(NormalizeVolumeToStep(scaled));
  }

// SL behind swing, then clamped to ATR guardrail range.
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

// 90% profit-capture rule from configured potential RR distance.
double GetTakeProfitBy90Rule(const bool buy,const double entry,const double sl)
  {
   // First preference: use a far-lookback multi-retest line and capture 90% of the path to that line.
   // This aligns TP with a practical market structure level rather than only a theoretical RR line.
   double retestLevel=0.0;
   int retests=0;
   if(FindStrongRetestLine(buy,entry,retestLevel,retests))
     {
      double projectedMove=MathAbs(retestLevel-entry);
      if(projectedMove>0.0)
        {
         double capture=MathMax(0.0,MathMin(100.0,TAKE_PROFIT_CAPTURE_PERCENT))/100.0;
         double tpFromRetest=buy ? entry+(projectedMove*capture) : entry-(projectedMove*capture);
         return(tpFromRetest);
        }
     }

   // Fallback: classic risk-multiple target, still applying the same 90% capture rule.
   double riskDist=MathAbs(entry-sl);
   if(riskDist<=0.0)
      return(0.0);

   double potentialDist=riskDist*Inp_PotentialRR;
   double capture=MathMax(0.0,MathMin(100.0,TAKE_PROFIT_CAPTURE_PERCENT))/100.0;
   double tpDist=potentialDist*capture;

   if(buy)
      return(entry+tpDist);
   return(entry-tpDist);
  }

bool ExecuteTrade(const bool buy,const int score,const double volumeFactor,const string tag)
  {
   double atr=GetATR(1);
   if(atr<=0.0)
      return(false);

   double entry=buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(entry<=0.0)
      return(false);

   double sl=GetBalancedSL(buy,entry,atr);
   double tp=GetTakeProfitBy90Rule(buy,entry,sl);
   double slDist=MathAbs(entry-sl);
   if(slDist<=0.0 || tp<=0.0)
      return(false);

   // Minimum reward-to-risk gate: never take structurally hopeless targets.
   if(Inp_MinRR>0.0 && MathAbs(tp-entry) < slDist*Inp_MinRR)
     {
      Log("Skip order: RR too low ("+DoubleToString(MathAbs(tp-entry)/slDist,2)+" < "+DoubleToString(Inp_MinRR,2)+")");
      return(false);
     }

   // Step 1) risk-based volume (SL-aware); returns 0 when too small for broker step
   double volume=CalcVolumeByRisk(slDist);

   // Step 2) scale factor for add-on entries.
   volume=NormalizeVolumeToStep(volume*volumeFactor);

   // Step 3) min-lot policy: floor to min lot (opt-in) or skip the trade
   double volMin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(volume<volMin)
     {
      if(Inp_AllowMinLotFloor && volMin>0.0)
         volume=volMin;
      else
        {
         Log("Skip order: calculated lot "+DoubleToString(volume,2)+" below minimum "+DoubleToString(volMin,2)+" (equity too small for chosen risk)");
         return(false);
        }
     }

   // Step 4) cap volume by margin constraints so tiny balances remain safe.
   volume=CalcVolumeByMarginLimit(buy,volume);

   if(volume<=0.0)
     {
      Log("Skip order: not enough free margin for min volume at current leverage/margin settings");
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

   Log((buy?"BUY":"SELL")+" opened. score="+(string)score+" tag="+tag);
   return(true);
  }

void TryScaleIn(const bool buy,const int score)
  {
   if(!ENABLE_SCALE_IN || score<Inp_MinScoreToTrade)
      return;

   int adds=(buy?g_scaleInAddsBuy:g_scaleInAddsSell);
   if(adds>=MAX_SCALE_IN_ADDS)
      return;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=Inp_MagicNumber)
         continue;

      bool posBuy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      if(posBuy!=buy)
         continue;

      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double tp=PositionGetDouble(POSITION_TP);
      if(tp<=0.0)
         return;

      double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double totalMove=MathAbs(tp-entry);
      if(totalMove<=0.0)
         return;

      double progress=MathAbs(price-entry)/totalMove;
      if(progress<SCALE_IN_TRIGGER_TO_TP)
         return;

      if(ExecuteTrade(buy,score,SCALE_IN_FACTOR,buy?"Falcon ScaleIn Buy":"Falcon ScaleIn Sell"))
        {
         if(buy) g_scaleInAddsBuy++;
         else g_scaleInAddsSell++;
        }
      return;
     }
  }

// Determines whether a reversal is strong enough to justify closing an active position.
// We treat "clear reversal" as: opposite trend context + opposite trigger + opposite sweep/wick.
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

// Manage active positions with "hold until clear reversal" behavior.
// Returns true when at least one EA position remains open after management.
bool ManageOpenPositions(const ENUM_TREND_STATE trend)
  {
   bool hasOpen=false;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol || PositionGetInteger(POSITION_MAGIC)!=Inp_MagicNumber)
         continue;

      hasOpen=true;
      bool buy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);

      if(Inp_HoldUntilClearReversal)
        {
         if(IsClearReversalAgainstPosition(buy,trend))
           {
            if(!ExtTrade.PositionClose(_Symbol))
               Log("Reversal close failed. retcode="+(string)ExtTrade.ResultRetcode()+" msg="+ExtTrade.ResultRetcodeDescription());
            else
               Log("Position closed on clear reversal signal");
           }
        }
      else
        {
         // Original management mode: keep ATR-based trailing active.
         double atr=GetATR(0);
         if(atr<=0.0)
            continue;

         double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double oldSL=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP);
         double newSL=buy ? price-atr*TRAIL_ATR_MULT : price+atr*TRAIL_ATR_MULT;
         bool improve=(buy && newSL>oldSL) || (!buy && (newSL<oldSL || oldSL==0.0));

         if(improve)
           {
            ExtTrade.SetExpertMagicNumber(Inp_MagicNumber);
            if(!ExtTrade.PositionModify(_Symbol,NormalizeDouble(newSL,_Digits),tp))
               Log("Trail modify failed. retcode="+(string)ExtTrade.ResultRetcode()+" msg="+ExtTrade.ResultRetcodeDescription());
           }
        }
     }

   return(hasOpen && CountOurPositions()>0);
  }

void SyncScaleInState()
  {
   if(CountOurPositions()==0)
     {
      g_scaleInAddsBuy=0;
      g_scaleInAddsSell=0;
     }
  }

int OnInit(void)
  {
   if(Inp_ATR_Period<2 || Inp_MinScoreToTrade<1 || Inp_MinScoreToTrade>5)
      return(INIT_PARAMETERS_INCORRECT);

   if(RETEST_LOOKBACK_FAR<ARC_LOOKBACK || MIN_RETESTS_FOR_LEVEL<2)
      return(INIT_PARAMETERS_INCORRECT);

   if(MIN_RISK_DOLLARS<0.0 || MIN_FREE_MARGIN_PERCENT<0.0 || MIN_FREE_MARGIN_PERCENT>=95.0)
      return(INIT_PARAMETERS_INCORRECT);

   atrHandle=iATR(_Symbol,_Period,Inp_ATR_Period);
   if(atrHandle==INVALID_HANDLE)
      return(INIT_FAILED);

   ArraySetAsSeries(atrBuffer,true);
   Log("Initialized");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   if(atrHandle!=INVALID_HANDLE)
     {
      IndicatorRelease(atrHandle);
      atrHandle=INVALID_HANDLE;
     }
   Log("Deinitialized reason="+(string)reason);
  }

void OnTick(void)
  {
   if(TRADE_ON_NEW_BAR_ONLY && !IsNewBar())
      return;

   SyncScaleInState();

   ENUM_TREND_STATE trend=GetMarketStructureTrend(Inp_TrendLookback);
   bool hasOpenPositions=ManageOpenPositions(trend);

   int scoreBuy=CalculateScore5(true,trend);
   int scoreSell=CalculateScore5(false,trend);

   Log("trend="+(string)trend+" buyScore="+(string)scoreBuy+" sellScore="+(string)scoreSell);

   // While a position is active, do not open a fresh opposite leg.
   // Only allow controlled scale-in into existing direction.
   if(hasOpenPositions)
     {
      TryScaleIn(true,scoreBuy);
      TryScaleIn(false,scoreSell);
      return;
     }

   // Strict trend-following: trade only WITH a directional structure, never in
   // consolidation. (The old strongReversal escape was unreachable at MinScore=5
   // and has been removed.)
   if(trend==TREND_UP && scoreBuy>=Inp_MinScoreToTrade)
      ExecuteTrade(true,scoreBuy,1.0,"Falcon Main Buy "+(string)scoreBuy+"/"+(string)Inp_MinScoreToTrade);
   else if(trend==TREND_DOWN && scoreSell>=Inp_MinScoreToTrade)
      ExecuteTrade(false,scoreSell,1.0,"Falcon Main Sell "+(string)scoreSell+"/"+(string)Inp_MinScoreToTrade);

   TryScaleIn(true,scoreBuy);
   TryScaleIn(false,scoreSell);
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
