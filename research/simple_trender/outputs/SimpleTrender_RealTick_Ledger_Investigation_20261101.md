# Simple Trender: real-tick ledger investigation

Date: 2026-11-01. This is a descriptive analysis of the existing USTECm MT5 real-tick runner tests. **No new strategy runs were made and no trailing stop was simulated.** Each month restarted at $1,000, 1:2000 leverage, 3% nominal total symbol stop risk and the EA's 90% sizing buffer. The research entry is M1 EMA(low)30 reclaim, VWAP17, M5 slope3, frozen M5 band stop, one fixed 1R leg and an M15/EMA210 runner exit. October is October 1–25.

## The large runners

| Period | Measured runners | Reached ≥5R | Entry dates with ≥5R runner | Net for ≥5R group | Median peak | Median realized net R | Median giveback | Median holding time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| July | 107 | 11 | 10 | +$1,080.46 | 10.12R | 5.25R | 5.49R | 17.4 h |
| August | 111 | 11 | 10 | +$546.33 | 8.86R | 3.57R | 4.61R | 14.4 h |
| September | 103 | 11 | 9 | +$620.57 | 7.72R | 4.57R | 5.37R | 8.9 h |
| October 1–25 | 72 | 12 | 10 | +$773.49 | 9.39R | 3.48R | 6.72R | 16.5 h |

The 45 large runners include 18 that closed at ≥5R net and seven that closed at a loss. August runner position 8, entered August 3 at 07:26 broker time, reached 10.56R and closed at −1.01R net; another August runner reached 30.20R and closed at +25.18R net. These examples show both the potential cost of giveback and the risk of cutting the occasional unusually large winner.

The 5R group contributed positive net in every month, but the other runners collectively lost $951.02 / $765.03 / $599.16 / $610.55 in July / August / September / October. Those figures include the three unmeasured end-of-test runners in the “other” group. Monthly figures come from independent accounts; adding them is not a portfolio return.

Holding time is entry to final exit, **not time to peak**. The MFE is the highest executable-side quote observed by the EA while the position was open, relative to its entry-to-original-stop distance. The ledger does not record the peak timestamp or the sequence of pullbacks. Consequently, the ledger alone cannot calculate whether a trailing stop would have survived to the peak, whether a stop could be modified in time, or what it would have earned.

## Runners that reached 1R but not 5R

| Period | Runners | Closed negative | Stopped at original stop | Net | Median peak | Median final net R | Median holding time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| July | 41 | 27 | 14 | −$309.40 | 2.14R | −0.60R | 4.0 h |
| August | 34 | 24 | 15 | −$83.39 | 1.67R | −0.54R | 2.2 h |
| September | 33 | 20 | 8 | −$81.06 | 1.83R | −0.30R | 4.7 h |
| October 1–25 | 24 | 15 | 13 | −$101.43 | 1.96R | −1.00R | 2.5 h |

Across the observed periods, 86 of 132 in this retrospective group closed negative. An exit activated at 5R would never activate for these trades under the observed baseline path. Earlier protection is worth studying, but the group is defined using its eventual peak: it cannot be identified as such at 1R, and a tighter stop can also close future 5R+ winners before they reach their peak.

Of 393 measured runners, 177 reached at least 1R and 45 of those reached at least 5R before the existing exit. This 45/177 is a descriptive, conditional count under the current rules, not a forecast or a result for a changed stop. One runner in each of August, September and October lacks an exit MFE because MT5 closed it at the end of the test; those three are excluded from both MFE cohorts.

## Fixed leg closed by the runner's M15 exit

| Period | Fixed legs closed by M15 | Positive / closed | Net of those early exits | Median MFE before exit | 1R TP / all normally closed fixed legs | Net of all fixed legs |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| July | 49 | 6 / 49 | −$344.67 | 0.35R | 79 / 178 | +$20.67 |
| August | 30 | 5 / 30 | −$114.81 | 0.43R | 78 / 185 | −$143.70 |
| September | 43 | 5 / 43 | −$204.95 | 0.44R | 80 / 176 | +$95.90 |
| October 1–25 | 31 | 2 / 31 | −$231.58 | 0.38R | 72 / 145 | +$219.46 |

Across the 153 M15-closed fixed legs, 18 were positive and 135 negative. This does **not** show that holding them to their own TP or SL would improve the result: their subsequent prices and the changed occupancy of the fixed slot must be replayed. The EA currently closes leg 2 when the M15 runner close succeeds, and also has an orphan check that attempts to close leg 2 when no runner remains. An independent fixed-leg variant would have to address both behaviors and define how it blocks further entries while that leg remains open.

## Sizing and execution observations

The runner's median actual planned stop risk was $15.24 / $10.61 / $11.28 / $17.96 in July / August / September / October. Risk varies with equity, stop distance, lot rounding, the concurrent cap and execution. The EA sizes each leg from half of the 3% input, applies its 90% buffer, and caps combined modeled stop risk; the figures are not a guarantee of the maximum loss through a gap or a rejected exit.

The EA logged “minimum volume exceeds risk” 70 / 39 / 28 / 32 times. These are logged **attempts**, not necessarily unique missed entries, and the same log message can also occur when the available combined risk budget is exhausted. It is not proof that each attempt failed solely because of broker minimum lot. Lower-risk comparisons must re-run the sizing and broker volume checks; neither filled trade counts nor drawdowns can be inferred by scaling these results.

The real-tick ledgers contain 6 / 6 / 10 / 3 market-closed errors on runner-close requests. The eventual trades are in the reconciled ledgers, but rejected requests and possible delayed closes remain part of the observed outcome. A future stop experiment needs to log each proposed, accepted, rejected and retried modification and enforce the broker's tick grid, stop distance and freeze limits.

## Three hypotheses to preserve for later testing

These are **research designs, not results or chosen settings**. Entry remains frozen. Their levels are simple starting points, not values established by these data.

1. **Earlier protection:** after the runner's executable-side quote first reaches +1R, request a stop at its entry price; never loosen it, and retain the M15 exit. Entry-price break-even is not guaranteed net break-even after costs or slippage.
2. **Large-move protection:** after +5R, trail the best executable-side quote by 3 times the original price-to-stop distance, never loosening the stop, while retaining the M15 exit. At activation the theoretical stop is +2R, but an actual request or fill may differ.
3. **Independent fixed leg:** let the fixed leg end at its own stop or 1R target after the runner exits, disabling both automatic M15 closure and orphan cleanup for this variant. Keep at most one fixed leg; do not open a new runner while that fixed leg remains, and retain the combined stop-risk cap. Compare this before changing the fixed target.

For all three, use complete real-tick replays before comparing returns: changing exit timing changes later entries, equity, sizing and risk occupancy. Audit trading costs, market closures, rejected changes and end-of-test positions. Then compare lower risk inputs such as 0.5%, 1%, and 2% to the 3% baseline as separate sizing experiments, with actual volume rounding, minimum-volume/budget skips, margin and drawdown measured anew. These are candidate research inputs, not risk recommendations.

July–October are development periods because their outcomes have been reviewed. Freeze any selected rule and sizing before an untouched chronological validation period; verify broker data availability without inspecting that period's strategy results. Select on the joint evidence for net expectancy, drawdown, entry frequency, cost sensitivity and retention of large runners, rather than the best single month or peak.

## Data and checks

Maps accompany this report: 45 runners with ≥5R MFE, 132 runners with 1R–<5R MFE, and 153 fixed legs closed by M15. They include entry and exit times in broker-server time, position ID, direction, original stop, volume, planned dollar risk, peak MFE, final net R and USD, holding time and exit reason. Peak time is explicitly marked “not recorded.” MFE/giveback are price-based; net R includes the recorded cash result and costs divided by planned dollar risk.

The analysis verified the real-tick quality and date windows, positive bar and tick counts, trade count and net against each MT5 summary, event START/END, and every non-end-of-test trade's MFE against its exit event. The original reports and event-ledger reconciliation remain in the real-tick archives. Results are historical simulations and do not establish live profitability.
