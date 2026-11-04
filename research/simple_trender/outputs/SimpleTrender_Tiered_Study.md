# M15 tiered runner study

Each run starts with a separate $1,000 account and spans July 1–October 25, 2026 continuously on USTECm real ticks. All use current-equity sizing with the existing 90% reserve, an M5 initial stop, an independent 1R fixed leg and the M15 runner exit. The three-leg version adds an independent 2R target, with initial risk divided across three legs.

| Configuration | Nominal risk | Entries | Net | Final balance | PF | Maximum equity DD | 1R net | 2R net | Runner net | Runner mean R |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| two-leg | 3% | 171 | $937.90 | $1937.90 | 1.33 | 23.68% (380.19) | $689.86 | $0.00 | $248.04 | 0.144 |
| two-leg | 4.5% | 171 | $1466.41 | $2466.41 | 1.31 | 33.67% (643.79) | $1159.95 | $0.00 | $306.46 | 0.144 |
| three-leg | 3% | 153 | $1172.63 | $2172.63 | 1.46 | 21.58% (367.06) | $512.78 | $472.37 | $187.48 | 0.153 |
| three-leg | 4.5% | 153 | $2193.79 | $3193.79 | 1.47 | 31.31% (711.65) | $1000.43 | $872.85 | $320.51 | 0.161 |

R averages exclude end-of-test exits but include rollback exits; dollar net includes all exits. R uses each leg’s own initial stop risk and should not be added as if it were account-level expectancy. Initial lot rounding, different entry paths and equity-dependent sizing can affect all outcomes.

| Configuration | Risk | 1R TP / TP+SL | 2R TP / TP+SL | Runner peaks ≥5R / ≥10R / ≥15R | Minimum-volume skips | Order-check skips | Close errors |
|---|---:|---:|---:|---:|---:|---:|---:|
| two-leg | 3% | 104 / 170 | 0 / 0 | 14 / 8 / 4 | 0 | 0 | 6 |
| two-leg | 4.5% | 104 / 170 | 0 / 0 | 14 / 8 / 4 | 0 | 0 | 6 |
| three-leg | 3% | 95 / 150 | 54 / 121 | 12 / 7 / 4 | 0 | 0 | 6 |
| three-leg | 4.5% | 95 / 149 | 54 / 120 | 12 / 7 / 4 | 0 | 0 | 6 |

Peak thresholds overlap and measure excursions before the original exit, not realized profit.

## Monthly account snapshots

Balances and equity are sampled at the first available tick of each broker-server month. Closed-trade net is assigned to the month of final exit; October ends October 25. Positions remain open across month boundaries.

| Configuration | Risk | Month | Balance | Equity | Open positions | Closed-trade net |
|---|---:|---|---:|---:|---:|---:|
| two-leg | 3% | 202607 | $1000.00 | $1000.00 | 0 | $206.84 |
| two-leg | 3% | 202608 | $1206.84 | $1206.84 | 0 | $221.88 |
| two-leg | 3% | 202609 | $1428.72 | $1428.72 | 0 | $208.14 |
| two-leg | 3% | 202610 | $1636.86 | $1636.86 | 0 | $301.04 |
| two-leg | 4.5% | 202607 | $1000.00 | $1000.00 | 0 | $289.44 |
| two-leg | 4.5% | 202608 | $1289.44 | $1289.44 | 0 | $312.98 |
| two-leg | 4.5% | 202609 | $1602.42 | $1602.42 | 0 | $328.23 |
| two-leg | 4.5% | 202610 | $1930.65 | $1930.65 | 0 | $535.76 |
| three-leg | 3% | 202607 | $1000.00 | $1000.00 | 0 | $305.32 |
| three-leg | 3% | 202608 | $1305.32 | $1305.32 | 0 | $211.14 |
| three-leg | 3% | 202609 | $1516.46 | $1516.46 | 0 | $127.36 |
| three-leg | 3% | 202610 | $1643.82 | $1643.82 | 0 | $528.81 |
| three-leg | 4.5% | 202607 | $1000.00 | $1000.00 | 0 | $494.37 |
| three-leg | 4.5% | 202608 | $1494.37 | $1494.37 | 0 | $409.80 |
| three-leg | 4.5% | 202609 | $1904.17 | $1904.17 | 0 | $216.07 |
| three-leg | 4.5% | 202610 | $2120.24 | $2120.24 | 0 | $1073.55 |

## Implementation and limitations

The 2R tier is a separate broker position (leg 4), with the same initial stop. Its target and the 1R tier are independent of M15 runner exits. Opening new three-leg sets is best-effort with retryable rollback if a leg cannot be opened or post-fill modeled risk exceeds the cap; a rejected close can delay rollback. Repeat 1R orders remain allowed while a runner is open. Modeled open risk is entry-to-stop for this EA and symbol; it is not a global portfolio or current-equity-to-stop risk measure.

The 3% tiered run recorded 7 rollback starts, of which 2 involved opened positions; the 4.5% tiered run recorded 8, of which 3 involved opened positions. Remaining rollback starts followed failed initial orders. Rollback exits and their costs are included in the results.

All reports require 100% real ticks and reconcile to their trade/event ledgers. Commission, spread, lot rounding, available margin, rejection and execution behavior are reflected in these tester results, but real fills may differ. July–October are development data, so these results cannot establish a reliable edge or select a live risk level.
