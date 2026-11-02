# Simple Trender: quantitative research and first test rules

**Update 2026-10-27:** ST-Q1 below is superseded by [SimpleTrender_MarketScan_Research.md](SimpleTrender_MarketScan_Research.md). Its H4 EMA200 + three M15 closes + M5 arrow chain was a hypothesis, not an established edge. The newer plan tests an H4 market scan and closed M15 entries across available Exness symbols. Keep this file as the original research and audit trail.

Date: 2026-10-27. Status: **research specification, not a live trading configuration**. The rules below are a fixed candidate to implement and test; the thresholds are design choices, not measured optima.

## What the research says, and what it does not

- Published time-series momentum work finds trend effects across diversified futures and forwards, primarily over **months**. It also scales positions by prior volatility. This supports testing a slow directional filter and consistent risk, but does **not** establish an edge for XAUUSD M5 arrows. [Moskowitz, Ooi and Pedersen (2012)](https://fairmodel.econ.yale.edu/ec439/mosk.pdf).
- A long-history trend study evaluates performance after estimated trading costs and fees. An intraday strategy with much higher turnover needs spread, commission, slippage and fill quality measured explicitly. [Hurst, Ooi and Pedersen (2017)](https://www.aqr.com/-/media/AQR/Documents/Insights/Journal-Article/AQR-JPM-Fall-2017.pdf).
- Selecting the best of many backtests can overfit. Freeze a small number of variants before testing and keep a genuinely unseen forward sample. [Bailey et al., *The Probability of Backtest Overfitting*](https://www.davidhbailey.com/dhbpapers/backtest-prob.pdf).
- Historical arrows on closed candles cannot reveal when a live arrow appeared or disappeared. [TradingView repainting documentation](https://www.tradingview.com/pine-script-docs/concepts/repainting/). The repo's real-tick probe found that only about 47–48% of first-sight M5 arrows remained at M5 close in its July and October samples (`Notes/M5-leads-M15-arrow-study.md`).
- MT5 real-tick tests use broker ticks where available, but can replace inconsistent or missing ticks with generated data. Check the history-quality field and execution logs, not merely the requested tester mode. [MQL5 Strategy Tester documentation](https://www.mql5.com/en/docs/runtime/testing).

## What the repository already establishes

- `Indicators/Simple Trender.txt` plots EMA(low,26), EMA(close,200), and EMA(VWAP,13). An up arrow requires close above EMA(low,26), previous close below the **current** smoothed VWAP, and current close above that VWAP. Down is symmetric. The 200 EMA does not control arrows. Pine comments describe stop entries beyond signal candle highs/lows; the EA variants currently use market entries.
- `Experts/LiveArrowM5EA.mq5` trades the first live M5 arrow, has optional structure and higher-timeframe band filters, a signal-candle stop, fixed R target, and risk checks. `Experts/ConfirmedArrowEA.mq5` waits for a closed M15 arrow and uses a different exit. Both are XAUUSD-only and require a hedging account.
- In `local_tester/reports/la5_bands_20261024_060137/summary.csv`, M5 arrow-only with a 1R target lost $2,394.31 over 361 development trades and $622.17 over 294 holdout trades. M15-band-only also lost in both periods. More restrictive filters often reduced trade count and drawdown; the available holdout rows are mixed and do not establish a robust profitable configuration.
- The screenshots in `Pics/Trend` show clean directional bands on some H4 and M15 moves, and repeated arrow/color changes during sideways or transition phases. They cover several markets, but cannot measure fills, costs, or live-arrow persistence. The EA's XAUUSD guard means the non-gold charts are illustrations, not tests of that EA.

## Candidate ST-Q1: H4 direction, M15 context, closed M5 trigger

All observations below use **completed bars only**. The first implementation should run on the broker's XAUUSD symbol, including a suffix such as `XAUUSDm`. Calculations use broker bars, broker-server calendar days for VWAP reset, typical price `(H+L+C)/3`, and tick volume; log these definitions because TradingView feeds can differ.

| Stage | Long rule | Short rule |
| --- | --- | --- |
| H4 direction | Last closed H4 close > its EMA(close,200) and > EMA(low,26); EMA(low,26) on that bar > its value three closed H4 bars earlier | Reverse all inequalities |
| M15 context | Last three closed M15 candles each closed > their EMA(low,26); latest closed M15 close > its EMA(VWAP,13) | Reverse all inequalities |
| M5 trigger | A **closed** M5 up arrow using the Pine formula above | A **closed** M5 down arrow |
| Entry | Place a buy stop one broker tick beyond the signal high, adjusted for the executable Ask and broker stop distance | Place a sell stop one broker tick below the signal low, adjusted for Bid and broker stop distance |
| Initial stop | One tick below the signal candle low | One tick above the signal candle high |
| Initial target | Two times the planned entry-to-stop price distance above the requested entry, rounded to the broker tick grid | Two times that distance below the requested entry, rounded to the broker tick grid |

Additional fixed rules:

1. Create at most one order attempt per M15 candle and hold at most one ST-Q1 position at a time. Do not reverse on an opposing M5 arrow; the original stop or target controls an open trade.
2. The pending entry can fill during the next **two M5 candles** after the signal close. Cancel it at the opening of the third bar, or immediately if a newly closed M15/H4 bar invalidates the directional context. Never move an unfilled entry toward price.
3. Before placement, require `(Ask - Bid) / abs(requested entry - stop) <= 0.10`. Reject invalid tick-grid prices, broker minimum stop-distance violations, missing data, and orders already crossed by the executable quote. Record the exact rejection reason.
4. Risk at most **0.5% of current equity** on one order, including an estimated commission and adverse execution allowance. Count all XAUUSD open and pending stop risk against a **2% combined account cap**. Round volume down to the broker step and skip if it falls below minimum lot; never round up to force a trade. Use `OrderCalcProfit` for the account-currency estimate. [MQL5 `OrderCalcProfit`](https://www.mql5.com/en/docs/trading/ordercalcprofit).
5. Stop placing new ST-Q1 orders for the broker-server day after the strategy's realized plus open P&L falls to **-2% of its start-of-day equity**. Existing protective stops and targets remain active. This is an entry halt, not a guarantee that losses cannot exceed 2% during gaps or slippage.
6. Attach the protective stop and target to the pending order. On a fill, record actual fill price, spread, slippage, commission, and actual R; if the broker permits, align the target to 2R of actual fill without widening the stop. Never increase size after entry.

`R` means the planned entry-to-stop price distance converted to account-currency loss. The sizing budget includes estimated costs, and **realized net R** includes actual spread, commission and slippage. Thus a nominal 2R target may yield less than 2R net. The exact spread and 0.5%/2% limits above are **initial research controls**. They are deliberately few and must not be retuned after seeing the forward sample.

## What must be added to the software

1. A shared indicator calculation for H4, M15 and M5 with a bar-by-bar parity audit against the Pine formula. Log VWAP day reset, volume source, and values at each signal. Keep all filter reads at shift 1 or older.
2. A closed-M5 signal state machine and real pending stop orders with two-bar expiry, context-change cancellation, restart recovery, one-attempt-per-M15 deduplication, and auditable transition logs.
3. Executable-quote spread and stop-distance checks, broker tick-grid normalization, `OrderCheck`, conservative account-currency sizing, commission/slippage accounting, and post-fill risk measurement. MT5 stop orders and fills are broker-dependent; requested price is not a guaranteed fill. [MQL5 order properties and execution modes](https://www.mql5.com/en/docs/constants/tradingconstants/orderproperties).
4. Account-level XAUUSD risk reservation and a persistent daily entry halt. Include positions and pending orders from other EAs, and handle missing stops conservatively.
5. A reproducible report per trade: H4/M15 state, M5 arrow time, order/fill/cancel time, spread, planned and actual R, MAE/MFE, exit cause, cost, and all skipped-signal counts. Keep indicator, filter, execution and exit metrics separate.

## Test protocol and decision gate

1. Implement only three **predeclared** variants with identical stop-entry, exit and cost logic: A = arrow only; B = H4 rule plus arrow; C = H4 + M15 rule plus arrow. ST-Q1 is C. This isolates what each filter adds. Do not select parameters by maximizing the old May–October report.
2. Reproduce known arrows and check all rules at exact decision times, including startup, day reset, order expiry, spread spikes, failed close/cancel, partial fill, and terminal restart. Preserve a signal-by-signal CSV for audit.
3. Use real-tick tester data and report actual history quality, spread, commissions, swap, requested versus executed prices and skipped entries. Run a cost stress with doubled measured spread and one extra tick of adverse entry slippage. Treat these as sensitivity tests, not broker guarantees.
4. May–October 2026 has already influenced this design, so it is **development/diagnostic data**. Freeze the rules, then use future paper/forward trading beginning after 2026-10-27 as the cleanest unseen sample. Record every attempted signal, including rejected orders. Do not revise ST-Q1 based on that sample and still call the same sample holdout.
5. Promotion requires positive **net** expectancy in R after costs across multiple forward periods, tolerable drawdown at the chosen risk, and no dependence on a handful of exceptional trades. Report trade count and uncertainty (for example, a bootstrap interval for mean net R). If the interval includes zero or the sample is small, record the result as inconclusive and keep collecting data. No live deployment follows from the existing screenshots or backtests alone.

The literature above motivates the research process. H4/M15/M5 choices and the numerical thresholds in ST-Q1 are a **test hypothesis**, not conclusions from those papers.
