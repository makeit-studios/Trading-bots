//+------------------------------------------------------------------+
//|                                   Pattern_Volume_Liquidity_EA.mq5 |
//|                          Multiple Entry Swing Trading System      |
//|                     Optimized for Small Accounts ($10 - $1000)   |
//+------------------------------------------------------------------+
#property copyright "Pattern + Volume + Wick Multi-Entry EA"
#property version   "2.00"
#property description "3 separate entries with individual targets"
#property description "Optimized for micro accounts with low inputs"
#property strict

// Include necessary libraries
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

// Create objects
CTrade trade;
CPositionInfo position;
CAccountInfo account;

//+------------------------------------------------------------------+
//| SIMPLIFIED INPUT PARAMETERS (Optimized for Small Accounts)       |
//+------------------------------------------------------------------+

// === Core Settings ===
input group "=== Core Settings ==="
input double   RiskPercent    = 1.0;           // % of account risked per signal (split into 3 tiers)
input int      RiskRewardTarget = 3;           // Average R:R target (1-5)
input bool     EnableWickFilter = true;        // Require wick rejection
input bool     EnableVolumeFilter = true;      // Require high volume

// === Advanced (Optional) ===
input group "=== Advanced Settings ==="
input int      MagicNumber = 223344;           // EA identifier
input int      MaxDailyTrades = 6;             // Max individual entries per day (3 per signal)
input double   MinStopLossPips = 15.0;         // Minimum SL distance
input double   MaxStopLossPips = 100.0;        // Maximum SL distance

//+------------------------------------------------------------------+
//| HARDCODED SETTINGS (To reduce inputs)                            |
//+------------------------------------------------------------------+

// Pattern detection
const int PIVOT_PERIOD = 5;                    // Fixed pivot sensitivity
const double PATTERN_TOLERANCE = 0.12;         // 12% tolerance

// Volume settings  
const int VOLUME_LOOKBACK = 20;                // Volume average period
const double VOLUME_THRESHOLD = 1.4;           // 1.4x = high volume

// Wick rejection
const double WICK_RATIO = 0.55;                // 55% wick to body minimum

// Multiple entries setup
const double ENTRY1_RR = 2.0;                  // Conservative target
const double ENTRY2_RR = 3.0;                  // Medium target  
const double ENTRY3_RR = 5.0;                  // Aggressive target

// Trading hours (GMT)
const int START_HOUR = 1;                      // Start 1 AM GMT
const int END_HOUR = 22;                       // End 10 PM GMT

// Circuit breakers (static)
#define MAX_DAILY_LOSS_PCT    5.0
#define MAX_DRAWDOWN_PCT      15.0
#define MAX_CONSECUTIVE_LOSS  4
#define COOLDOWN_HOURS        4
#define FRIDAY_CLOSE_HOUR     21
#define NEWS_BLOCK_MINUTES    30
#define SLIPPAGE_BUFFER_PTS   4.0

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
int atrHandle;
double atrBuffer[];
datetime lastBarTime = 0;
int tradesToday = 0;
datetime currentDay = 0;

struct RiskState {
   double   peakEquity;
   double   dayStartEquity;
   int      consecutiveLosses;
   datetime coolDownUntil;
   bool     halted;
   datetime haltTime;
};
RiskState risk;
string stateFileName;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
    atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
    if(atrHandle == INVALID_HANDLE)
    {
        Print("Failed to create ATR indicator");
        return(INIT_FAILED);
    }
    
    ArraySetAsSeries(atrBuffer, true);
    
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(20);
    
    stateFileName = "ClaudeEA_" + _Symbol + "_" + (string)_Period + ".json";
    LoadState();
    risk.dayStartEquity = account.Equity();
    
    Print("=== EA Initialized ===");
    Print("Account Balance: $", account.Balance());
    Print("Risk per Signal: ", RiskPercent, "% (3 tiers)");
    Print("Expected Targets: ", ENTRY1_RR, "R, ", ENTRY2_RR, "R, ", ENTRY3_RR, "R");
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    SaveState();
    if(atrHandle != INVALID_HANDLE)
        IndicatorRelease(atrHandle);
    
    Print("EA stopped. Total profit: $", account.Profit());
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBarTime == lastBarTime)
        return;
    lastBarTime = currentBarTime;
    
    NewDayCheck();
    
    if(!CanTrade()) return;
    
    if(CopyBuffer(atrHandle, 0, 0, 3, atrBuffer) < 0)
        return;
    
    if(tradesToday >= MaxDailyTrades)
        return;
    
    ManagePositions();
    
    int buyPositions = CountPositions(POSITION_TYPE_BUY);
    int sellPositions = CountPositions(POSITION_TYPE_SELL);
    
    if(buyPositions > 0 && sellPositions > 0)
        return;
    
    AnalyzeAndTrade();
}

//+------------------------------------------------------------------+
//| Analyze market and execute trades                                 |
//+------------------------------------------------------------------+
void AnalyzeAndTrade()
{
    // Get previous candle data (completed bar)
    double open1 = iOpen(_Symbol, PERIOD_CURRENT, 1);
    double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
    double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
    double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
    
    // Volume analysis
    bool volumeOK = true;
    if(EnableVolumeFilter)
    {
        double currentVolume = (double)iVolume(_Symbol, PERIOD_CURRENT, 1);
        double avgVolume = GetAverageVolume();
        volumeOK = currentVolume > (avgVolume * VOLUME_THRESHOLD);
    }
    
    if(!volumeOK)
        return;
    
    // Wick rejection analysis
    bool isBuySignal = false;
    bool isSellSignal = false;
    
    if(EnableWickFilter)
    {
        isBuySignal = CheckBuyRejection(open1, close1, high1, low1);
        isSellSignal = CheckSellRejection(open1, close1, high1, low1);
    }
    else
    {
        // Simple candle direction
        isBuySignal = close1 > open1;
        isSellSignal = close1 < open1;
    }
    
    // Execute multiple entries
    if(isBuySignal && CountPositions(POSITION_TYPE_BUY) == 0)
    {
        OpenMultipleBuyEntries(low1);
    }
    else if(isSellSignal && CountPositions(POSITION_TYPE_SELL) == 0)
    {
        OpenMultipleSellEntries(high1);
    }
}

//+------------------------------------------------------------------+
//| Open 3 buy positions with different targets                       |
//+------------------------------------------------------------------+
void OpenMultipleBuyEntries(double signalLow)
{
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    double stopLoss = signalLow - (10 * point * 10);
    double slDistance = entryPrice - stopLoss;
    double slPips = slDistance / (point * 10);
    
    if(slPips < MinStopLossPips || slPips > MaxStopLossPips)
    {
        Print("SL distance (", slPips, " pips) outside limits");
        return;
    }
    
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    
    double tierLot = CalcTierLot(slDistance);
    if(tierLot <= 0) return;
    
    string tags[] = {"Buy_T1_2R", "Buy_T2_3R", "Buy_T3_5R"};
    double mults[] = {ENTRY1_RR, ENTRY2_RR, ENTRY3_RR};
    bool anyOk = false;
    
    for(int t = 0; t < 3; t++) {
        double tp = NormalizeDouble(entryPrice + slDistance * mults[t], _Digits);
        if(trade.Buy(tierLot, _Symbol, 0.0, stopLoss, tp, tags[t])) {
            Print("BUY 3T ", tags[t], " vol=", tierLot, " TP=", tp);
            tradesToday++;
            anyOk = true;
        } else Print("BUY 3T ", tags[t], " FAIL err:", GetLastError());
    }
    
    if(anyOk)
        Print("=== 3 BUY entries | SL: ", slPips, " pips | Risk%: ", RiskPercent, " ===");
}

//+------------------------------------------------------------------+
//| Open 3 sell positions with different targets                      |
//+------------------------------------------------------------------+
void OpenMultipleSellEntries(double signalHigh)
{
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double stopLoss = signalHigh + (10 * point * 10);
    double slDistance = stopLoss - entryPrice;
    double slPips = slDistance / (point * 10);
    
    if(slPips < MinStopLossPips || slPips > MaxStopLossPips)
    {
        Print("SL distance (", slPips, " pips) outside limits");
        return;
    }
    
    stopLoss = NormalizeDouble(stopLoss, _Digits);
    
    double tierLot = CalcTierLot(slDistance);
    if(tierLot <= 0) return;
    
    string tags[] = {"Sell_T1_2R", "Sell_T2_3R", "Sell_T3_5R"};
    double mults[] = {ENTRY1_RR, ENTRY2_RR, ENTRY3_RR};
    bool anyOk = false;
    
    for(int t = 0; t < 3; t++) {
        double tp = NormalizeDouble(entryPrice - slDistance * mults[t], _Digits);
        if(trade.Sell(tierLot, _Symbol, 0.0, stopLoss, tp, tags[t])) {
            Print("SELL 3T ", tags[t], " vol=", tierLot, " TP=", tp);
            tradesToday++;
            anyOk = true;
        } else Print("SELL 3T ", tags[t], " FAIL err:", GetLastError());
    }
    
    if(anyOk)
        Print("=== 3 SELL entries | SL: ", slPips, " pips | Risk%: ", RiskPercent, " ===");
}

//+------------------------------------------------------------------+
//| Check for buy rejection (bullish wick)                            |
//+------------------------------------------------------------------+
bool CheckBuyRejection(double open, double close, double high, double low)
{
    if(close <= open) return false;  // Must be bullish
    
    double bodySize = close - open;
    if(bodySize == 0) return false;
    
    double lowerWick = MathMin(close, open) - low;
    double upperWick = high - MathMax(close, open);
    
    // Lower wick must be significant
    bool wickSizeOK = lowerWick >= (bodySize * WICK_RATIO);
    
    // Lower wick larger than upper
    bool wickDominant = lowerWick > (upperWick * 1.3);
    
    return wickSizeOK && wickDominant;
}

//+------------------------------------------------------------------+
//| Check for sell rejection (bearish wick)                           |
//+------------------------------------------------------------------+
bool CheckSellRejection(double open, double close, double high, double low)
{
    if(close >= open) return false;  // Must be bearish
    
    double bodySize = open - close;
    if(bodySize == 0) return false;
    
    double upperWick = high - MathMax(close, open);
    double lowerWick = MathMin(close, open) - low;
    
    // Upper wick must be significant
    bool wickSizeOK = upperWick >= (bodySize * WICK_RATIO);
    
    // Upper wick larger than lower
    bool wickDominant = upperWick > (lowerWick * 1.3);
    
    return wickSizeOK && wickDominant;
}

//+------------------------------------------------------------------+
//| Get average volume                                                |
//+------------------------------------------------------------------+
double GetAverageVolume()
{
    double sum = 0;
    for(int i = 1; i <= VOLUME_LOOKBACK; i++)
    {
        sum += (double)iVolume(_Symbol, PERIOD_CURRENT, i);
    }
    return sum / VOLUME_LOOKBACK;
}

//+------------------------------------------------------------------+
//| Calculate tier lot based on % risk                                |
//+------------------------------------------------------------------+
double CalcTierLot(double slDist)
{
    double cap = MathMin(account.Balance(), account.Equity());
    double totalRisk = cap * RiskPercent / 100.0;
    double tierRisk = totalRisk / 3.0;
    
    double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(tv <= 0 || ts <= 0 || slDist <= 0) return 0;
    
    double effDist = slDist + SLIPPAGE_BUFFER_PTS * pt;
    double lot = tierRisk / ((effDist / ts) * tv);
    
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    double vMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double vMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    lot = MathFloor(lot / step) * step;
    return MathMax(vMin, MathMin(vMax, lot));
}

//+------------------------------------------------------------------+
//| Count positions by type                                           |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type)
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(position.SelectByIndex(i))
        {
            if(position.Symbol() == _Symbol && 
               position.Magic() == MagicNumber &&
               position.PositionType() == type)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                     |
//+------------------------------------------------------------------+
bool IsTradingTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    if(dt.hour < START_HOUR || dt.hour >= END_HOUR)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
bool CanTrade() {
    if(risk.halted) {
        if(risk.haltTime > 0 && TimeCurrent() - risk.haltTime > 86400)
            risk.halted = false;
        else return false;
    }
    
    if(!IsTradingTime()) return false;
    
    double eq = account.Equity();
    
    if(eq > risk.peakEquity) risk.peakEquity = eq;
    double dd = risk.peakEquity > 0 ? (1.0 - eq / risk.peakEquity) * 100.0 : 0;
    if(dd >= MAX_DRAWDOWN_PCT) {
        if(!risk.halted) {
            risk.halted = true;
            risk.haltTime = TimeCurrent();
            Print("HALT: dd ", DoubleToString(dd,1), "% >= ", MAX_DRAWDOWN_PCT, "%");
            CloseAll("dd_halt");
        }
        return false;
    }
    
    double dayLoss = risk.dayStartEquity > 0 ? (1.0 - eq / risk.dayStartEquity) * 100.0 : 0;
    if(dayLoss >= MAX_DAILY_LOSS_PCT) return false;
    
    MqlDateTime dt;
    TimeCurrent(dt);
    int h = dt.hour, m = dt.min;
    if(h == 8 && m < NEWS_BLOCK_MINUTES) return false;
    if(h == 13 && m < NEWS_BLOCK_MINUTES) return false;
    if(dt.day_of_week == 5 && h == 13) return false;
    
    if(dt.day_of_week == 5 && h >= FRIDAY_CLOSE_HOUR) return false;
    
    return true;
}

//+------------------------------------------------------------------+
void NewDayCheck() {
    static int lastDay = 0;
    MqlDateTime dt;
    TimeCurrent(dt);
    if(dt.day == lastDay) return;
    lastDay = dt.day;
    risk.dayStartEquity = account.Equity();
    if(dt.day_of_week == 1) {
        risk.consecutiveLosses = 0;
        risk.coolDownUntil = 0;
    }
}

//+------------------------------------------------------------------+
void ManagePositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Magic() != MagicNumber) continue;
        if(position.Symbol() != _Symbol) continue;
        
        string cmt = position.Comment();
        if(StringFind(cmt, "_T1_") < 0 && StringFind(cmt, "_T2_") < 0 && StringFind(cmt, "_T3_") < 0) continue;
        
        double entry = position.PriceOpen();
        double curSL = position.StopLoss();
        if(curSL == 0) continue;
        double riskD = MathAbs(entry - curSL);
        double breakeven = (entry > curSL) ? entry + riskD : entry - riskD;
        
        double price = SymbolInfoDouble(_Symbol, position.PositionType() == POSITION_TYPE_BUY ? SYMBOL_BID : SYMBOL_ASK);
        bool reachedBE = position.PositionType() == POSITION_TYPE_BUY ? (price >= breakeven) : (price <= breakeven);
        
        if(reachedBE) {
            double pt = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double newSL = (entry > curSL) ? entry - SLIPPAGE_BUFFER_PTS * pt : entry + SLIPPAGE_BUFFER_PTS * pt;
            bool needMod = (entry > curSL) ? (curSL < newSL) : (curSL > newSL);
            if(needMod) {
                if(trade.PositionModify(position.Ticket(), newSL, position.TakeProfit()))
                    Print("BE ", cmt);
            }
        }
    }
}

//+------------------------------------------------------------------+
void CloseAll(string reason) {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Magic() != MagicNumber || position.Symbol() != _Symbol) continue;
        if(trade.PositionClose(position.Ticket()))
            Print("Closed ", position.Ticket(), " ", reason);
    }
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &req,
                        const MqlTradeResult &res) {
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD) {
        HistorySelect(0, TimeCurrent());
        int total = HistoryDealsTotal();
        if(total <= 0) return;
        ulong ticket = HistoryDealGetTicket(total - 1);
        if(ticket <= 0) return;
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) return;
        
        double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
        if(profit < 0) {
            risk.consecutiveLosses++;
            if(risk.consecutiveLosses >= MAX_CONSECUTIVE_LOSS) {
                risk.coolDownUntil = TimeCurrent() + COOLDOWN_HOURS * 3600;
                Print("Cooldown: ", risk.consecutiveLosses, " losses. Resume ", TimeToString(risk.coolDownUntil));
            }
        } else if(profit > 0) {
            risk.consecutiveLosses = 0;
            risk.coolDownUntil = 0;
        }
    }
}

//+------------------------------------------------------------------+
void SaveState() {
    string j = "{";
    j += "\"pe\":" + DoubleToString(risk.peakEquity,2) + ",";
    j += "\"de\":" + DoubleToString(risk.dayStartEquity,2) + ",";
    j += "\"cl\":" + (string)risk.consecutiveLosses + ",";
    j += "\"cd\":" + (string)risk.coolDownUntil + ",";
    j += "\"ha\":" + (risk.halted?"1":"0") + ",";
    j += "\"ht\":" + (string)risk.haltTime;
    j += "}";
    
    int h = FileOpen(stateFileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
    if(h != INVALID_HANDLE) { FileWrite(h, j); FileClose(h); }
}

//+------------------------------------------------------------------+
void LoadState() {
    risk.peakEquity = account.Equity();
    risk.dayStartEquity = account.Equity();
    
    int h = FileOpen(stateFileName, FILE_READ|FILE_TXT|FILE_COMMON);
    if(h == INVALID_HANDLE) return;
    string j = FileReadString(h);
    FileClose(h);
    
    risk.peakEquity       = JGetD(j, "pe", account.Equity());
    risk.dayStartEquity   = JGetD(j, "de", account.Equity());
    risk.consecutiveLosses = (int)JGetD(j, "cl", 0);
    risk.coolDownUntil    = (datetime)JGetD(j, "cd", 0);
    risk.halted           = JGetD(j, "ha", 0) > 0.5;
    risk.haltTime         = (datetime)JGetD(j, "ht", 0);
    
    Print("State loaded: peakEq=", DoubleToString(risk.peakEquity,2));
}

//+------------------------------------------------------------------+
double JGetD(string json, string key, double def) {
    string s = "\"" + key + "\":";
    int p = StringFind(json, s);
    if(p < 0) return def;
    p += StringLen(s);
    int e = StringFind(json, ",", p);
    int e2 = StringFind(json, "}", p);
    if(e < 0 || (e2 >= 0 && e2 < e)) e = e2;
    if(e < 0) return def;
    string v = StringSubstr(json, p, e - p);
    StringReplace(v, " ", "");
    return (v == "" || v == "null") ? def : StringToDouble(v);
}

//+------------------------------------------------------------------+
//| Display account info on chart                                     |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    // Optional: Add chart display of account stats
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        Print("=== Account Status ===");
        Print("Balance: $", account.Balance());
        Print("Equity: $", account.Equity());
        Print("Profit: $", account.Profit());
        Print("Open Positions: ", PositionsTotal());
        Print("Trades Today: ", tradesToday, "/", MaxDailyTrades);
    }
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