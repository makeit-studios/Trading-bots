# Live M5 arrow comparison

`Experts/LiveArrowM5EA.mq5` is a separate XAUUSD strategy. The confirmed M15 arrow EA and the zone EA remain available without changes.

## Rules

- The Simple Trender arrow is computed on every M5 tick. The first tick on which it appears is actionable; the candle does **not** have to close. A live arrow may disappear later. Only the first observed arrow per M5 candle is acted on, even if that candle's live arrow flips.
- `ArrowOnly` uses the signal directly. `Aligned` requires the already known H4 and M15 structure to match the signal before a new entry. An opposite first-sight arrow closes all of this EA's old-side trades in either mode. If a close fails, the new side is blocked. Several same-side trades can coexist on a hedging account.
- The initial stop is the M5 signal candle's exact low (buy) or high (sell) **at the first-sight tick**. It is not extended if the candle makes a later extreme. A buy's target is entry plus the selected multiple of initial risk; a sell's is entry minus that multiple. The target is rounded to the broker tick grid in the favorable direction and attached with the stop to the market order. Actual reward/risk can differ slightly if the market fill slips from the requested price.
- Targets compared: 1:1 and 1:2. Positions otherwise close only at the stop or on an opposite live arrow. The former HH/LL and structure-break exits are not used in this comparison.
- The risk budget remains 1% of equity per arrow and 4% combined XAUUSD stop risk, including other positions and pending orders on the same broker symbol. Exact stops that fail broker rules are skipped. A hedging account is required for separate entries.

## Chart and log

Gray M5 arrows are live. Green/red arrows indicate an arrow still present on a closed bar. Yellow `M5 FIRST BUY/SELL` text marks the actual first-sight decision even if that arrow later disappears. Aqua entry, tomato stop, and gold target lines show open trades. The panel gives H4/M15 structure, filter, target, current risk, and the current decision. The MT5 journal and `LiveArrowM5EA_events.csv` record timestamped `LA5 SIGNAL`, `ORDER`, `EXIT`, `REVERSE`, and `SKIP` events.

## Reproduce tests

After closing MT5, run `powershell -NoProfile -ExecutionPolicy Bypass -File local_tester/run_la5_compare.ps1` in this repository. The four fixed `.set` files compare both entry filters with 1:1 and 1:2 targets across May–July 2026 development and August–October 2026 holdout windows. Optimization is disabled. The script uses the local Exness `XAUUSDm` hedging demo and `Model=4`, which requests real ticks. Check the report's history-quality field for actual coverage.

Run `powershell -NoProfile -ExecutionPolicy Bypass -File local_tester/run_la5_visual.ps1 -Filter ArrowOnly -TargetR 1` for the visible October 18–20 M5 replay. Close that MT5 session before running the same command with `-TargetR 2` or `-Filter Aligned`.

The October 18–20 smoke test used 100% real ticks, took 31 trades with 1:1 arrow-only settings, ended at $9,992.10 from $10,000, and reported zero failed controlled assertions. The journal showed both stop and target fills and an opposite-arrow close before a new-side order.
