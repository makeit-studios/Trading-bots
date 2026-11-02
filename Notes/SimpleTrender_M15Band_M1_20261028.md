# Simple Trender M15-band and M1 execution study

Date: 2026-10-28. Status: development evidence from July and October 2026. August and September were not tested.

## Implemented modes

- `ENTRY_SWING_CONTROL=0`: original M15 plus selected H1/H4 confirmed swing gate.
- `ENTRY_M15_BAND=1`: closed M5 arrow with completed M15 band direction and regime gate.
- `ENTRY_M1_M5_M15=2`: closed M1 arrow with both completed M5 and M15 band directions matching. The initial entry does not require a width state. M15 contraction or compression blocks repeat 1R additions.
- `EXIT_FIXED_R=0`, `EXIT_RUNNER=1`, and `EXIT_BAND_RUNNER=2` retain their numeric values for reproducibility.

The M1 mode freezes its stop one broker tick outside the M1 signal band. The persistent runner keeps its original stop, uses no trailing or break-even movement, and exits from completed M15 adverse-band or EMA200 events. H1 and H4 remain audit information in the new modes.

## M5 baseline: four symbols

All 24 runs used 100% real-tick history and all 196 positions reconciled with the MT5 reports.

| Configuration | Month | Accepted entries | Entries/calendar day | Fixed win rate | Fixed expectancy | All-leg expectancy |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Swing control fixed | July | 44 | 1.42 | 36.36% | -0.2764R | -0.2764R |
| Swing control fixed | October | 33 | 1.32 | 63.64% | +0.2798R | +0.2798R |
| M15 band fixed | July | 18 | 0.58 | 50.00% | +0.0028R | +0.0028R |
| M15 band fixed | October | 24 | 0.96 | 33.33% | -0.3362R | -0.3362R |
| M15 band runner | July | 18 | 0.58 | 50.00% | +0.0029R | -0.1439R |
| M15 band runner | October | 24 | 0.96 | 33.33% | -0.3362R | +0.4004R |

The October M15 runner result contains a large BTC winner. The result is not broad: its fixed legs lost, and the July runner configuration was negative overall.

## M1/M5/M15 direction test: October

| Configuration | Accepted entries | Entries/calendar day | Entries/active entry day | Fixed win rate | Fixed expectancy | All-leg expectancy |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| M1 fixed | 74 | 2.96 | 4.11 | 35.14% | -0.3115R | -0.3115R |
| M1 runner | 73 | 2.92 | 4.06 | 35.62% | -0.3014R | -0.4777R |

The M1 mode nearly reached the 3–5 calendar-day target and reached it on days when at least one entry occurred. It did not reach the 55–60% fixed-leg win-rate target.

### M1 fixed results by symbol

| Symbol | Trades | Win rate | Net | Expectancy |
| --- | ---: | ---: | ---: | ---: |
| XAUUSDm | 14 | 50.00% | +$1.83 | +0.0046R |
| BTCUSDm | 21 | 23.81% | -$507.66 | -0.5498R |
| EURUSDm | 21 | 33.33% | -$335.57 | -0.3603R |
| USTECm | 18 | 38.89% | -$180.22 | -0.2224R |

### M1 runner results by symbol

| Symbol | Completed legs | Fixed-leg win rate | Net | All-leg expectancy |
| --- | ---: | ---: | ---: | ---: |
| XAUUSDm | 26 | 53.85% | -$137.57 | -0.2169R |
| BTCUSDm | 41 | 23.81% | -$622.61 | -0.6997R |
| EURUSDm | 41 | 33.33% | -$493.71 | -0.5502R |
| USTECm | 34 | 38.89% | -$245.25 | -0.3218R |

## Decision

Moving execution to M1 increased trade count enough to study, but M5 plus M15 directional agreement did not create a positive fixed-leg edge with the M1 band stop. The M1 runner also lost on every selected symbol in October. The next change should isolate the cause rather than add more filters: compare the same M1 entries with the wider frozen M5 signal band stop, or require a better M1 trigger location within the M5 band. Do not combine both changes in one run.

Artifacts:

- `local_tester/reports/trender_runner_dev_m15band_complete`
- `local_tester/reports/trender_runner_dev_m1_fixed_oct_20261028`
- `local_tester/reports/trender_runner_dev_m1_runner_oct_20261028`
