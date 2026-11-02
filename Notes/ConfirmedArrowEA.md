# Confirmed M15 arrow EA

`Experts/ConfirmedArrowEA.mq5` is a separate XAUUSD Expert Advisor. It does not use zones or change `StructureZoneEntryEA`.

## Trading rules

- A Simple Trender arrow on a **closed M15 candle** is evaluated at the next bar. Gray arrows on the live candle are provisional and cannot place orders. Green and red arrows on closed candles are confirmed.
- `ArrowOnly` accepts every confirmed arrow that passes execution and risk checks. `Aligned` additionally requires H4 and M15 structure to agree with the arrow. Swing lengths are fixed at H4 21 and M15 3 for this comparison.
- An opposite confirmed arrow closes all this EA's positions on the old side before evaluating the new entry. An unaligned opposite arrow still closes the old side in `Aligned` mode. A failed close blocks the new entry. Same-direction arrows can add separate positions on a hedging account.
- Each entry risks at most the selected percentage of equity, initially 1%. The stop is the signal candle's exact low for a buy or high for a sell. Existing XAUUSD stop risk, including other EAs' positions and pending orders, counts toward the combined cap, initially 4%. The EA skips a trade if broker minimum volume, stop distance, margin, or server checks cannot meet these prices and limits.
- A buy exits at the available market price when a newly formed M15 HH pivot confirms after entry; a sell exits on a newly formed LL. A closed opposing M15 structural break can exit sooner. Pivot labels confirm three M15 bars after the pivot, so neither the exit nor the chart label is backdated as a trading decision. There is no fixed take profit.

## Reading the visual chart

- The panel shows the selected filter, H4 and M15 structure, most recent arrow, open risk and the current reason to enter, wait, exit, or skip.
- Confirmed arrows, provisional arrows, confirmed swing labels and levels, entries, exact stops, exits, and reversals have separate chart marks and tooltips. Trade marks remain for the most recent 50 deals.
- The Experts/Tester journal prints timestamped `CAE SIGNAL`, `CAE ORDER`, `CAE EXIT`, `CAE REVERSE`, and `CAE SKIP` lines. `ConfirmedArrowEA_events.csv` in the MT5 file sandbox records the same decisions.

## Reproduce the comparisons

Run `local_tester/run_cae_compare.ps1` after closing MT5. It installs the compiled EA and compares the two fixed parameter sets (`CAE_arrow_only.set` and `CAE_aligned.set`) on identical windows. Optimization is disabled. It saves HTML reports under `local_tester/reports/`.

Run `local_tester/run_cae_visual.ps1 -Filter ArrowOnly` for a visible October 18–20 replay. After closing that MT5 session, run `local_tester/run_cae_visual.ps1 -Filter Aligned` to inspect the filtered version. The script uses the local Exness `XAUUSDm` demo symbol. Adjust the script's symbol if your broker names gold differently.

## Fixed comparison results

Initial balance $10,000; Exness demo XAUUSDm; M15; modeled ticks (`Model=0`); no parameter optimization. Development: May–July 2026. Holdout: August–October 2026.

| Period | Filter | Trades | Expectancy per trade | Net profit | Max equity drawdown | Skipped arrows |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Development | Arrow only | 295 | −$7.20 | −$2,125.00 | 39.83% | 1 |
| Development | H4 + M15 aligned | 46 | −$20.05 | −$922.51 | 11.27% | 250 |
| Holdout | Arrow only | 254 | −$8.29 | −$2,106.54 | 26.93% | 0 |
| Holdout | H4 + M15 aligned | 56 | −$22.74 | −$1,273.64 | 13.68% | 198 |

Source reports: `local_tester/reports/cae_compare_20261023_053223/`. Both filters lost money in development and holdout. These results do not support live use as a profitable strategy. Tester ticks are modeled, and the MQL5 daily VWAP uses broker tick volume, so arrow timing may differ from TradingView.

The compiled final build has 0 errors and 0 warnings. Its controlled replay checks reported 0 failures, and the post-logging-change smoke test reproduced the same 10 trades and −$529.83 result. The full comparison preceded the logging-only change. A forced broker close rejection and an interrupted tester restart were not simulated; those paths are implemented defensively but still need a dedicated execution test.

An audit of the four HTML reports processed every deal in time order (92, 590, 112, and 508 deals respectively). None showed simultaneous open buy and sell volume from this EA; all four ended flat. Up to three same-direction buys and two same-direction sells were open during the comparisons. Tester journals contain both new-HH/LL and opposing-structure exits, along with reversal events.
