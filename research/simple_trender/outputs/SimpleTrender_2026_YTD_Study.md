# Simple Trender: 2026 year-to-date real-tick study

Requested period: 2026-01-01 through 2026-11-02 inclusive; MT5 excludes the current day. Each run starts with a separate $1,000 continuous account on USTECm using the M15 three-leg system and current-equity sizing. Each uses independent 1R and 2R legs and the original M15 runner exit, with the M5 initial stop and no break-even or ATR trail.

| Nominal risk | Actual event span | Entries | Net | Final balance | Profit factor | Maximum equity drawdown | 1R net | 2R net | Runner net |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 3% | 2026.01.01 00:00:00 – 2026.11.02 23:59:58 | 383 | $-33.05 | $966.95 | 0.99 | 63.95% (895.89) | $6.63 | $54.82 | $-94.50 |
| 5% | 2026.01.01 00:00:00 – 2026.11.02 23:59:58 | 384 | $-310.08 | $689.92 | 0.95 | 84.26% (1 472.67) | $-103.65 | $-129.68 | $-76.75 |

| Nominal risk | 1R TP / TP+SL | 2R TP / TP+SL | 1R mean net R | 2R mean net R | Runner mean net R | Runner peak ≥5R / ≥10R / ≥15R |
|---:|---:|---:|---:|---:|---:|---:|
| 3% | 193 / 377 | 113 / 317 | 0.020 | 0.056 | -0.019 | 33 / 17 / 12 |
| 5% | 193 / 374 | 109 / 312 | 0.025 | 0.032 | -0.013 | 33 / 17 / 12 |

R averages exclude end-of-test positions but include rollback exits; net cash includes all exits. Target-hit denominators include only TP and SL exits. Runner MFE thresholds overlap and are peak excursions, not realized profit. Leg-level R values use each leg’s own initial risk.

## Monthly account snapshots

Balance and equity are measured on the first available broker tick of each month; positions are carried across month boundaries. Closed-trade net is attributed to the month of final exit and includes the trade’s full costs. November contains November 1–2 only.

| Nominal risk | Month | First-tick balance | First-tick equity | Open positions | Closed-trade net |
|---:|---|---:|---:|---:|---:|
| 3% | 202601 | $1000.00 | $1000.00 | 0 | $121.11 |
| 3% | 202602 | $1121.11 | $1145.53 | 1 | $-250.14 |
| 3% | 202603 | $870.97 | $870.97 | 0 | $365.59 |
| 3% | 202604 | $1236.56 | $1236.56 | 0 | $-522.73 |
| 3% | 202605 | $713.83 | $713.83 | 0 | $-133.01 |
| 3% | 202606 | $580.82 | $580.82 | 0 | $-64.45 |
| 3% | 202607 | $516.37 | $516.37 | 0 | $173.73 |
| 3% | 202608 | $690.10 | $690.10 | 0 | $32.08 |
| 3% | 202609 | $722.18 | $722.18 | 0 | $71.34 |
| 3% | 202610 | $793.52 | $793.52 | 0 | $210.37 |
| 3% | 202611 | $1003.89 | $1006.48 | 1 | $-36.94 |
| 5% | 202601 | $1000.00 | $1000.00 | 0 | $228.71 |
| 5% | 202602 | $1228.71 | $1275.33 | 1 | $-368.59 |
| 5% | 202603 | $860.12 | $860.12 | 0 | $559.16 |
| 5% | 202604 | $1419.28 | $1419.28 | 0 | $-934.00 |
| 5% | 202605 | $485.28 | $485.28 | 0 | $-137.31 |
| 5% | 202606 | $347.97 | $347.97 | 0 | $-62.73 |
| 5% | 202607 | $285.24 | $285.24 | 0 | $162.68 |
| 5% | 202608 | $447.92 | $447.92 | 0 | $7.67 |
| 5% | 202609 | $455.59 | $455.59 | 0 | $57.15 |
| 5% | 202610 | $512.74 | $512.74 | 0 | $222.65 |
| 5% | 202611 | $735.39 | $738.50 | 1 | $-45.47 |

## Risk and execution

The EA applies a 90% sizing reserve: the nominal 3% and 5% settings correspond to an intended maximum of 2.7% and 4.5% of current equity, respectively, before lot rounding and execution effects. Modeled open risk is entry-to-stop on matching EA positions for this symbol, not account-wide or current-equity-to-stop exposure. Gaps, slippage, rejected requests and market closures can produce larger losses.

| Risk | Successful tier sets | Rollback starts | Rollbacks with opened positions | Minimum-volume skips | Order-check skips | Close errors |
|---:|---:|---:|---:|---:|---:|---:|
| 3% | 317 | 75 | 6 | 70 | 0 | 10 |
| 5% | 312 | 72 | 10 | 59 | 0 | 10 |

Reports and event ledgers were reconciled and checked for 100% real-tick history. July–October were used in strategy development, so the full period is mixed in-sample/out-of-sample, not an untouched validation.
