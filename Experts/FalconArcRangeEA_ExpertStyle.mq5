//+------------------------------------------------------------------+
//|                            FalconArcRangeEA.mq5                  |
//|      Falcon Score-Based Pattern EA (MT5) - Expert-style form     |
//+------------------------------------------------------------------+
#property copyright "Falcon"
#property link      "https://www.mql5.com"
#property version   "1.10"
#property strict

//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string Inp_Expert_Title          ="FalconArcRangeEA";

//--- risk & execution
input int    Inp_MagicNumber           =12003;
input double Inp_RiskPercent           =10.0;   // requested safer live range: 10..20% per trade
input double Inp_SL_ATR_Mult           =1.2;
input double Inp_Trail_ATR_Mult        =1.0;

//--- scoring
input int    Inp_MinScoreToTrade       =5;
input int    Inp_ArcLookback           =5;      // range to find the double peak/trough
input double Inp_ArcTolerancePts       =20.0;   // points tolerance for curve trigger
input double Inp_MomentumBodyMinRatio  =0.60;   // body/range threshold for momentum breakout trigger

//--- indicator settings
input int    Inp_ATR_Period            =14;

//--- debug / fallback
input bool   Inp_DebugLogs             =true;
input bool   Inp_AllowTrendlessEntry   =true;   // fallback direction when trend score is neutral
input double Inp_FixedLotFallback      =0.01;   // used if risk lot calculation returns <= 0
input bool   Inp_HoldUntilClearReversal=true;   // hold open trades until strong opposite reversal appears

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CTrade   ExtTrade;
datetime lastBarTime=0;
int      atrHandle=INVALID_HANDLE;
double   atrBuffer[];

//+------------------------------------------------------------------+
//| Utility logging                                                  |
//+------------------------------------------------------------------+
void Log(const string msg)
  {
   if(Inp_DebugLogs)
      Print("[",Inp_Expert_Title,"] ",msg);
  }

//+------------------------------------------------------------------+
//| Utility: New bar                                                 |
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
//| Utility: ATR                                                     |
//+------------------------------------------------------------------+
double GetATR(const int index)
  {
   if(atrHandle==INVALID_HANDLE)
      return(0.0);

   if(CopyBuffer(atrHandle,0,index,1,atrBuffer)<1)
      return(0.0);

   return(atrBuffer[0]);
  }

//+------------------------------------------------------------------+
//| Utility: count strategy positions                                |
//+------------------------------------------------------------------+
int CountOurPositions()
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;

      string sym=PositionGetString(POSITION_SYMBOL);
      long   mg =PositionGetInteger(POSITION_MAGIC);

      if(sym==_Symbol && mg==Inp_MagicNumber)
         count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
//| Trigger: Arc/Curve                                               |
//+------------------------------------------------------------------+
bool IsArcTrigger(const bool buy)
  {
   if(Inp_ArcLookback<3)
      return(false);

   double currentLevel=buy ? iLow(_Symbol,_Period,1) : iHigh(_Symbol,_Period,1);

   for(int i=3;i<=Inp_ArcLookback;i++)
     {
      double pastLevel=buy ? iLow(_Symbol,_Period,i) : iHigh(_Symbol,_Period,i);
      if(MathAbs(currentLevel-pastLevel)<=Inp_ArcTolerancePts*_Point)
         return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Trigger: Momentum breakout                                       |
//+------------------------------------------------------------------+
bool IsMomentumTrigger(const bool buy)
  {
   double body=MathAbs(iClose(_Symbol,_Period,1)-iOpen(_Symbol,_Period,1));
   double range=iHigh(_Symbol,_Period,1)-iLow(_Symbol,_Period,1);
   if(range<=0.0)
      return(false);

   double ratio=body/range;
   if(buy && iClose(_Symbol,_Period,1)>iHigh(_Symbol,_Period,2) && ratio>=Inp_MomentumBodyMinRatio)
      return(true);
   if(!buy && iClose(_Symbol,_Period,1)<iLow(_Symbol,_Period,2) && ratio>=Inp_MomentumBodyMinRatio)
      return(true);

   return(false);
  }

//+------------------------------------------------------------------+
//| Score: Wick                                                      |
//+------------------------------------------------------------------+
int WickScore()
  {
   double h=iHigh(_Symbol,_Period,1);
   double l=iLow(_Symbol,_Period,1);
   double o=iOpen(_Symbol,_Period,1);
   double c=iClose(_Symbol,_Period,1);

   double r=h-l;
   if(r<=0.0)
      return(0);

   double upperWick=h-MathMax(o,c);
   double lowerWick=MathMin(o,c)-l;

   if((upperWick/r>=0.6 || lowerWick/r>=0.6) && (MathAbs(c-o)/r<=0.4))
      return(3);

   return(0);
  }

//+------------------------------------------------------------------+
//| Score: Trend                                                     |
//+------------------------------------------------------------------+
int TrendDirection()
  {
   int bull=0;
   int bear=0;

   for(int i=1;i<=3;i++)
     {
      if(iClose(_Symbol,_Period,i)>iOpen(_Symbol,_Period,i))
         bull++;
      else if(iClose(_Symbol,_Period,i)<iOpen(_Symbol,_Period,i))
         bear++;
     }

   if(bull==3)
      return(1);
   if(bear==3)
      return(-1);

   return(0);
  }

//+------------------------------------------------------------------+
//| Score: Correction                                                |
//+------------------------------------------------------------------+
bool IsCorrection()
  {
   double a1=GetATR(1);
   double a4=GetATR(4);
   if(a1<=0.0 || a4<=0.0)
      return(false);

   return(a1<a4);
  }

//+------------------------------------------------------------------+
//| Score: Pattern                                                   |
//+------------------------------------------------------------------+
int PatternScore()
  {
   double h1=iHigh(_Symbol,_Period,1), h3=iHigh(_Symbol,_Period,3);
   double l1=iLow(_Symbol,_Period,1),  l3=iLow(_Symbol,_Period,3);

   if(MathAbs(h1-h3)<(h3-l3)*0.3)
      return(2); // flag-style compression

   if(h1<h3 && l1>l3)
      return(1); // wedge-style inside

   return(0);
  }

//+------------------------------------------------------------------+
//| Utility: volume by risk                                          |
//+------------------------------------------------------------------+
double CalcVolumeByRisk(const double slDistPrice)
  {
   if(slDistPrice<=0.0)
      return(0.0);

   double equity   =AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney=equity*(Inp_RiskPercent/100.0);

   double tickSize =SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   double volMin   =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double volMax   =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volStep  =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(tickSize<=0.0 || tickValue<=0.0 || volStep<=0.0)
      return(0.0);

   double lossPerLot=(slDistPrice/tickSize)*tickValue;
   if(lossPerLot<=0.0)
      return(0.0);

   double rawLots=riskMoney/lossPerLot;
   double lots=MathFloor(rawLots/volStep)*volStep;

   if(lots<volMin)
      lots=volMin;
   if(lots>volMax)
      lots=volMax;

   return(NormalizeDouble(lots,2));
  }

//+------------------------------------------------------------------+
//| Utility: normalize to broker step                                |
//+------------------------------------------------------------------+
double NormalizeVolumeToStep(const double lots)
  {
   double volMin=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double volMax=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(volStep<=0.0)
      return(0.0);

   double v=MathFloor(lots/volStep)*volStep;
   if(v<volMin)
      v=volMin;
   if(v>volMax)
      v=volMax;

   return(NormalizeDouble(v,2));
  }

//+------------------------------------------------------------------+
//| Execute order                                                    |
//+------------------------------------------------------------------+
void Execute(const bool buy)
  {
   double atr=GetATR(1);
   if(atr<=0.0)
     {
      Log("Skip trade: ATR unavailable");
      return;
     }

   double entry = buy ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double slDist=atr*Inp_SL_ATR_Mult;
   if(entry<=0.0 || slDist<=0.0)
     {
      Log("Skip trade: invalid entry/sl distance");
      return;
     }

   double sl=buy ? (entry-slDist) : (entry+slDist);

   double impulse=MathAbs(iHigh(_Symbol,_Period,5)-iLow(_Symbol,_Period,5));
   if(impulse<=0.0)
      impulse=atr;

   double tp=buy ? (entry+impulse*0.45) : (entry-impulse*0.45);
   double vol=CalcVolumeByRisk(slDist);

   if(vol<=0.0)
     {
      vol=NormalizeVolumeToStep(Inp_FixedLotFallback);
      Log("Risk volume invalid. Fallback volume="+DoubleToString(vol,2));
     }

   if(vol<=0.0)
     {
      Log("Skip trade: volume invalid even after fallback");
      return;
     }

   ExtTrade.SetExpertMagicNumber(Inp_MagicNumber);
   bool ok=false;

   if(buy)
      ok=ExtTrade.Buy(vol,_Symbol,0.0,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),"Falcon Buy");
   else
      ok=ExtTrade.Sell(vol,_Symbol,0.0,NormalizeDouble(sl,_Digits),NormalizeDouble(tp,_Digits),"Falcon Sell");

   if(!ok)
      Log("OrderSend failed. retcode="+(string)ExtTrade.ResultRetcode()+" msg="+ExtTrade.ResultRetcodeDescription()+
          " price="+DoubleToString(entry,_Digits)+" sl="+DoubleToString(sl,_Digits)+" tp="+DoubleToString(tp,_Digits));
   else
      Log("Order placed. ticket="+(string)ExtTrade.ResultOrder()+" vol="+DoubleToString(vol,2));
  }

//+------------------------------------------------------------------+
//| Trailing stop management                                         |
//+------------------------------------------------------------------+
void ManageTrailing()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;

      string sym=PositionGetString(POSITION_SYMBOL);
      long mg   =PositionGetInteger(POSITION_MAGIC);

      if(sym!=_Symbol || mg!=Inp_MagicNumber)
         continue;

      double atr=GetATR(0);
      if(atr<=0.0)
         continue;

      bool buy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);
      double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double newSL=buy ? price-atr*Inp_Trail_ATR_Mult : price+atr*Inp_Trail_ATR_Mult;
      double oldSL=PositionGetDouble(POSITION_SL);
      double tp   =PositionGetDouble(POSITION_TP);

      bool improve=(buy && newSL>oldSL) || (!buy && (newSL<oldSL || oldSL==0.0));
      if(!improve)
         continue;

      ExtTrade.SetExpertMagicNumber(Inp_MagicNumber);
      bool modOK=ExtTrade.PositionModify(_Symbol,NormalizeDouble(newSL,_Digits),tp);
      if(!modOK)
         Log("Trail modify failed. retcode="+(string)ExtTrade.ResultRetcode()+" msg="+ExtTrade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Detect clear reversal against active position                    |
//+------------------------------------------------------------------+
bool IsClearReversalAgainstPosition(const bool positionIsBuy)
  {
   int trend=TrendDirection();

   if(positionIsBuy)
     {
      bool oppositeTrend=(trend==-1);
      bool oppositeSignal=(IsArcTrigger(false) || IsMomentumTrigger(false));
      return(oppositeTrend && oppositeSignal);
     }

   bool oppositeTrend=(trend==1);
   bool oppositeSignal=(IsArcTrigger(true) || IsMomentumTrigger(true));
   return(oppositeTrend && oppositeSignal);
  }

//+------------------------------------------------------------------+
//| Manage active trades: hold until clear reversal                  |
//+------------------------------------------------------------------+
bool ManageOpenPositions()
  {
   bool hasOpen=false;

   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0)
         continue;

      string sym=PositionGetString(POSITION_SYMBOL);
      long mg   =PositionGetInteger(POSITION_MAGIC);
      if(sym!=_Symbol || mg!=Inp_MagicNumber)
         continue;

      hasOpen=true;
      bool buy=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY);

      // In hold mode: keep position alive unless we get a strong opposite signal.
      if(Inp_HoldUntilClearReversal)
        {
         if(IsClearReversalAgainstPosition(buy))
           {
            ExtTrade.SetExpertMagicNumber(Inp_MagicNumber);
            if(!ExtTrade.PositionClose(_Symbol))
               Log("Reversal close failed. retcode="+(string)ExtTrade.ResultRetcode()+" msg="+ExtTrade.ResultRetcodeDescription());
            else
               Log("Position closed on clear reversal");
           }
        }
      else
        {
         // If hold mode is disabled, run normal trailing logic to keep loss controlled.
         double atr=GetATR(0);
         if(atr<=0.0)
            continue;

         double price=buy ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK);
         double newSL=buy ? price-atr*Inp_Trail_ATR_Mult : price+atr*Inp_Trail_ATR_Mult;
         double oldSL=PositionGetDouble(POSITION_SL);
         double tp   =PositionGetDouble(POSITION_TP);
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

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   // Avoid hard input rejection to keep tester runs smooth.
   // If an invalid ATR period is supplied, fall back to 14 instead of failing init.
   int atrPeriod=(Inp_ATR_Period<2 ? 14 : Inp_ATR_Period);

   atrHandle=iATR(_Symbol,_Period,atrPeriod);
   if(atrHandle==INVALID_HANDLE)
     {
      Print(__FUNCTION__+": failed creating ATR handle");
      return(INIT_FAILED);
     }

   ArraySetAsSeries(atrBuffer,true);

   Log("Initialized successfully");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(atrHandle!=INVALID_HANDLE)
     {
      IndicatorRelease(atrHandle);
      atrHandle=INVALID_HANDLE;
     }

   Log("Deinitialized. reason="+(string)reason);
  }

//+------------------------------------------------------------------+
//| Tick event                                                       |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   if(!IsNewBar())
      return;

   bool hasOpenPositions=ManageOpenPositions();

   int score=WickScore();
   int trend=TrendDirection();

   if(trend!=0)
      score+=2;
   if(IsCorrection())
      score+=2;

   score+=PatternScore();

   Log("score="+(string)score+" trend="+(string)trend);

   if(score<Inp_MinScoreToTrade)
     {
      Log("No entry: score below threshold");
      return;
     }

   bool buyArc =IsArcTrigger(true);
   bool sellArc=IsArcTrigger(false);
   bool buyMomentum=IsMomentumTrigger(true);
   bool sellMomentum=IsMomentumTrigger(false);

   bool buyTrigger=(buyArc || buyMomentum);
   bool sellTrigger=(sellArc || sellMomentum);

   Log("triggers: buyArc="+(buyArc?"1":"0")+" sellArc="+(sellArc?"1":"0")+
       " buyMom="+(buyMomentum?"1":"0")+" sellMom="+(sellMomentum?"1":"0"));

   if(hasOpenPositions)
     {
      Log("Holding active position until clear reversal");
      return;
     }

   if(trend==1 && buyTrigger)
     {
      Log("Entry confirmed: trend BUY + trigger BUY -> executing");
      Execute(true);
      return;
     }

   if(trend==-1 && sellTrigger)
     {
      Log("Entry confirmed: trend SELL + trigger SELL -> executing");
      Execute(false);
      return;
     }

   if(Inp_AllowTrendlessEntry)
     {
      if(trend==0)
        {
         bool lastBull=(iClose(_Symbol,_Period,1)>iOpen(_Symbol,_Period,1));
         bool lastBear=(iClose(_Symbol,_Period,1)<iOpen(_Symbol,_Period,1));

         if(buyTrigger && lastBull)
           {
            Log("Entry confirmation (trendless): BUY trigger + bullish candle -> executing");
            Execute(true);
            return;
           }

         if(sellTrigger && lastBear)
           {
            Log("Entry confirmation (trendless): SELL trigger + bearish candle -> executing");
            Execute(false);
            return;
           }
        }

      if(trend==1 && !buyTrigger && sellTrigger)
        {
         Log("Entry blocked: bullish trend but only SELL trigger matched");
         return;
        }

      if(trend==-1 && !sellTrigger && buyTrigger)
        {
         Log("Entry blocked: bearish trend but only BUY trigger matched");
         return;
        }
     }

   Log("Entry confirmed conditions not complete; no order sent");
  }

//+------------------------------------------------------------------+
//| Trade event                                                      |
//+------------------------------------------------------------------+
void OnTrade(void)
  {
   // kept for Expert-style form compatibility
  }

//+------------------------------------------------------------------+
//| Timer event                                                      |
//+------------------------------------------------------------------+
void OnTimer(void)
  {
   // kept for Expert-style form compatibility
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
