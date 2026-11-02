//+------------------------------------------------------------------+
//|                                    RSI_Oversold_Overbought_EA.mq5|
//|  RSI Expert Advisor in MetaQuotes Expert framework style         |
//+------------------------------------------------------------------+
#property copyright "Custom"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Expert/Expert.mqh>
#include <Expert/Signal/SignalRSI.mqh>
#include <Expert/Trailing/TrailingNone.mqh>
#include <Expert/Money/MoneyFixedLot.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                           |
//| All values below are exposed in Strategy Tester parameter UI.    |
//+------------------------------------------------------------------+
//--- expert inputs
input string Inp_Expert_Title   ="RSI_Oversold_Overbought_EA";
input int    Inp_MagicNumber    =20260223;
input bool   Inp_EveryTick      =false;

//--- signal inputs
input int    Inp_RSI_Period      =14;
input ENUM_APPLIED_PRICE Inp_RSI_Price=PRICE_CLOSE;
input double Inp_RSI_Oversold    =30.0;
input double Inp_RSI_Overbought  =70.0;
input int    Inp_Signal_StopLoss =300; // points
input int    Inp_Signal_TakeProfit=600; // points

//--- money inputs
input double Inp_Money_Lots      =0.10;

//+------------------------------------------------------------------+
//| Global expert object                                             |
//+------------------------------------------------------------------+
CExpert ExtExpert;

//+------------------------------------------------------------------+
//| Initialization function                                          |
//+------------------------------------------------------------------+
// Main initialization routine for framework components.
// Creates/attaches signal, trailing, and money modules with validation.
int OnInit(void)
  {
//--- sanity checks
   if(Inp_RSI_Period<2)
     {
      Print(__FUNCTION__+": RSI period must be >= 2");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(Inp_RSI_Oversold<=0.0 || Inp_RSI_Oversold>=50.0 ||
      Inp_RSI_Overbought<=50.0 || Inp_RSI_Overbought>=100.0 ||
      Inp_RSI_Oversold>=Inp_RSI_Overbought)
     {
      Print(__FUNCTION__+": invalid oversold/overbought settings");
      return(INIT_PARAMETERS_INCORRECT);
     }

//--- initialize expert core
   if(!ExtExpert.Init(Symbol(),Period(),Inp_EveryTick,Inp_MagicNumber))
     {
      Print(__FUNCTION__+": error initializing expert");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

//--- create RSI signal
   CSignalRSI *signal=new CSignalRSI;
   if(signal==NULL)
     {
      Print(__FUNCTION__+": error creating RSI signal");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

//--- attach signal
   if(!ExtExpert.InitSignal(signal))
     {
      Print(__FUNCTION__+": error initializing signal");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

//--- configure RSI signal
   signal.PeriodRSI(Inp_RSI_Period);
   signal.Applied(Inp_RSI_Price);
   // NOTE:
   // Some MT5 include versions of CSignalRSI do not expose Shift/LowLevel/HighLevel setters.
   // To keep broad compiler compatibility, we avoid calling those missing methods here.
   // Oversold/overbought inputs are kept for validation/documentation and can be mapped
   // to framework-specific setters if your local SignalRSI.mqh provides them.
   signal.StopLevel(Inp_Signal_StopLoss);
   signal.TakeLevel(Inp_Signal_TakeProfit);

//--- validate signal settings
   if(!signal.ValidationSettings())
     {
      Print(__FUNCTION__+": RSI signal parameters invalid");
      ExtExpert.Deinit();
      return(INIT_PARAMETERS_INCORRECT);
     }

//--- trailing: none
   CTrailingNone *trailing=new CTrailingNone;
   if(trailing==NULL)
     {
      Print(__FUNCTION__+": error creating trailing object");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   if(!ExtExpert.InitTrailing(trailing))
     {
      Print(__FUNCTION__+": error initializing trailing object");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   if(!trailing.ValidationSettings())
     {
      Print(__FUNCTION__+": trailing parameters invalid");
      ExtExpert.Deinit();
      return(INIT_PARAMETERS_INCORRECT);
     }

//--- money management: fixed lot
   CMoneyFixedLot *money=new CMoneyFixedLot;
   if(money==NULL)
     {
      Print(__FUNCTION__+": error creating money object");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   if(!ExtExpert.InitMoney(money))
     {
      Print(__FUNCTION__+": error initializing money object");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   money.Lots(Inp_Money_Lots);

   if(!money.ValidationSettings())
     {
      Print(__FUNCTION__+": money parameters invalid");
      ExtExpert.Deinit();
      return(INIT_PARAMETERS_INCORRECT);
     }

//--- init indicators used by framework
   if(!ExtExpert.InitIndicators())
     {
      Print(__FUNCTION__+": error initializing indicators");
      ExtExpert.Deinit();
      return(INIT_FAILED);
     }

   Print("[",Inp_Expert_Title,"] initialized successfully");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Deinitialization function                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ExtExpert.Deinit();
   Print("[",Inp_Expert_Title,"] deinitialized. reason=",reason);
  }

//+------------------------------------------------------------------+
//| Function-event handler "tick"                                   |
//+------------------------------------------------------------------+
// Tick event delegated to the MetaQuotes Expert framework core.
// Framework handles signal evaluation and trade lifecycle.
void OnTick(void)
  {
   ExtExpert.OnTick();
  }

//+------------------------------------------------------------------+
//| Function-event handler "trade"                                  |
//+------------------------------------------------------------------+
void OnTrade(void)
  {
   ExtExpert.OnTrade();
  }

//+------------------------------------------------------------------+
//| Function-event handler "timer"                                  |
//+------------------------------------------------------------------+
void OnTimer(void)
  {
   ExtExpert.OnTimer();
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
