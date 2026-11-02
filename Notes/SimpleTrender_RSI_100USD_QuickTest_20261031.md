# Simple Trender — RSI and $100 quick test

**Run date:** 2026-10-31 (Atlantic/Reykjavik)  
**Development windows:** July 1–31 and October 1–25, 2026. August and September were not tested.  
**Tester:** Exness demo symbols, MT5 model 2 (open prices only), generated OHLC. This is a fast approximation, not a real-tick or live result. Each report starts a separate account; dollar profits must not be added into one portfolio return.

## Rules tested

- BTCUSDm: completed M3 arrow, EMA(low)23, smoothed VWAP11, M5 direction slope2, frozen M5 band stop.
- USTECm: completed M1 arrow, EMA(low)30, smoothed VWAP17 (and runner comparison with VWAP15), M5 direction slope3, frozen M5 band stop.
- RSI gate: RSI(14, close) on the completed entry bar; **buy only if RSI > 70**, **sell only if RSI < 35**. The gate applies after M5 alignment and before sizing or opening a position. It is optional in the EA so the unfiltered control remains reproducible.
- Fixed test: one 1R leg with 0.5% nominal planned stop risk and a 10% sizing reserve. Runner test: separate runner and 1R legs at 0.25% nominal risk each, major EMA210 runner exit.
- Initial deposit: **$100** for the realistic sizing tests, **1:2000 leverage**. The $10,000 tests below isolate the RSI and runner effects from the broker minimum-volume constraint. Reports confirm the requested deposit and leverage.

## $100 account: actual MT5 fills

| Pair, fixed 1R without RSI | July entries / wins / net | October entries / wins / net |
| --- | --- | --- |
| BTCUSDm, VWAP11 | 5 / 4 / **+$1.02** | 4 / 3 / **+$0.70** |
| USTECm, VWAP17 | 0 / 0 / **$0.00** | 0 / 0 / **$0.00** |

USTEC produced 33 eligible July signals and 28 eligible October signals before sizing. All were skipped because the broker minimum lot exceeded the EA's $0.45 effective stop-risk budget at $100. The direct $100 RSI test in July left one eligible USTEC signal; it was also skipped for minimum volume. BTC produced 18 eligible July and 16 eligible October signals without RSI, but only 5 and 4, respectively, fit the volume/risk limit. That is **9 filled opportunities across 56 calendar days**, about **0.16 per day** for this two-pair setup, far below the 3–5-per-day target. The small BTC sample does not establish a profitable edge.

Leverage 1:2000 changes margin requirements; it does not reduce the dollar loss between entry and the frozen stop. The EA correctly declines a minimum lot when its stop loss exceeds the configured risk budget.

## RSI effect at $10,000 comparison size

| Pair, fixed 1R | Unfiltered July | RSI July | Unfiltered October | RSI October |
| --- | --- | --- | --- | --- |
| BTCUSDm VWAP11 | 15 entries, 9 wins, +$137.44 | **0 trades** | 14 entries, 7 wins, −$1.34 | **0 trades** |
| USTECm VWAP17 | 11 entries, 6 wins, +$45.60 | **1 trade, 0 wins, −$44.24** | 11 entries, 8 wins, +$224.64 | **0 trades** |

For BTC, RSI rejected all 18 July and 16 October signals that had passed the M5 direction gate. For USTEC, it rejected 32 of 33 July signals and all 28 October signals. The RSI version therefore provides too little activity to judge win rate or expectancy and makes the frequency problem worse. The one USTEC July fixed trade lost.

## USTEC runner comparison at $10,000

Each row is a separate account and full-month model-2 test. “Entries” counts an initial runner plus its 1R leg once. Net and profit factor include **all legs**. Median MFE and giveback refer to the runner.

| VWAP / month | Entries | Fixed wins | All-leg net | PF | Equity DD | Median runner MFE / giveback |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 13 / July (prior control) | 17 | 9/17 | +$317.84 | 1.85 | 2.83% | 0.704R / 1.702R |
| 15 / July | 16 | 10/16 | +$654.03 | 3.15 | 3.73% | 1.844R / 1.939R |
| **17 / July** | **12** | **8/12** | **+$699.44** | **4.68** | **3.69%** | **1.870R / 1.806R** |
| 13 / October (prior control) | 14 | 9/14 | +$659.40 | 3.96 | 1.80% | 2.242R / 1.534R |
| 15 / October | 12 | 7/12 | +$651.81 | 3.85 | 3.84% | 2.127R / 1.538R |
| **17 / October** | **11** | **8/11** | **+$676.19** | **4.71** | **3.40%** | **2.120R / 1.647R** |

VWAP17 made slightly more than VWAP15 in both development months, but took fewer entries. The older VWAP13 had lower October drawdown and more entries. These settings were selected using July and October, so the favorable numbers are **development evidence**, not holdout confirmation.

With RSI enabled, the VWAP17 runner made **+$4.22 from one July entry (two legs)** and took **zero October entries**. Its one July fixed leg exited early under the runner's M15 exit logic, so it should not be equated with the separate fixed 1R result.

## Current decision

Keep BTC and USTEC as the research focus. Keep RSI **off** in the working candidate: the proposed >70/<35 gate removed nearly every aligned entry. At a $100 balance and the current 0.5% stop-risk policy, USTEC is not tradable at the tested stop distances and broker minimum volume; higher leverage alone does not fix that. VWAP17 is the stronger USTEC runner *within these development tests*, with the frequency and drawdown tradeoffs shown above. Freeze a candidate before using August or September, then confirm with real ticks before drawing a deployment conclusion.

## Reproducibility

- EA: `Experts/TrenderRunnerResearchEA.mq5` and `.ex5`, compiled with **0 errors, 0 warnings**.
- Quick tester: `local_tester/run_trender_quick_screen.ps1`; `-Deposit` now defaults to 100, `-RsiEnabled` enables the 14-period gate, and 1:2000 leverage is specified in each tester config.
- Every new archive is under `local_tester/reports/trender_quick_*` with source/binary hashes, `.set`, `.ini`, MT5 `.htm`, events, `audited_summary.csv`, and trades. All 15 new runs were ledger-reconciled to their MT5 reports.

The MT5 tester allows an initial deposit and leverage setting and reports both in its results: [MetaTrader 5 Strategy Testing](https://www.metatrader5.com/en/terminal/help/algotrading/testing). The RSI gate reads the completed bar through the MQL5 indicator buffer: [iRSI](https://www.mql5.com/en/docs/indicators/irsi), [CopyBuffer](https://www.mql5.com/en/docs/series/copybuffer).
