# Simple Trender: independent fixed exit and retracement investigation

Research date: 2026-11-01. The research-only EA was modified so the fixed 1R leg remains open after the runner exits; the fixed leg ends at its own SL or TP, or is closed at the end of the test. M15 band/EMA changes still close the runner. A fixed leg left without a runner keeps its slot, and a new runner cannot start until it closes. The original combined risk cap, frozen entry and M5 stop remain in place.

Each run uses USTECm, M1 EMA(low)30 reclaim, smoothed VWAP17, M5 direction slope3, the frozen M5 band stop, M15/EMA210 runner exit, $1,000 starting balance, 1:2000 leverage, and 3% nominal combined stop-risk with the EA's 90% sizing buffer. MT5 model 4 reported 100% real ticks. Each month is a separate account; October covers October 1–25.

## Actual real-tick comparison

| Period | Entries baseline → independent | Combined net baseline → independent | Equity DD baseline → independent | Independent fixed TP / TP+SL | Independent fixed net | Independent runner net | Runners reaching 5R baseline → independent |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| July | 178 → 101 | +$150.11 → −$20.04 | 30.34% → 31.52% | 51 / 101 (50.5%) | −$42.25 | +$22.21 | 11 → 4 |
| August | 186 → 109 | −$362.40 → −$228.58 | 46.76% → 37.79% | 53 / 108 (49.1%) | −$43.71 | −$184.87 | 11 → 5 |
| September | 176 → 110 | +$117.31 → +$99.59 | 37.89% → 24.12% | 58 / 110 (52.7%) | +$34.34 | +$65.25 | 11 → 6 |
| October 1–25 | 146 → 98 | +$382.40 → −$44.85 | 24.15% → 29.20% | 51 / 97 (52.6%) | +$26.51 | −$71.36 | 12 → 7 |

Fixed TP rates exclude the one end-of-test fixed leg in August and the one in October. Of 416 TP/SL-resolved fixed legs across the independent tests, 213 hit TP (51.2%). Their unweighted mean realized net R was about +0.006R per resolved leg: mean TP +1.013R and mean SL −1.051R. This is close to flat in that sample and excludes two end-of-test closes. Dollar results differ with risk, lot sizes, timing and compounding. The samples are independent monthly accounts, not a combined portfolio.

The independent variant was better in August by net and drawdown, had lower September drawdown with slightly lower net, and was worse by net in July and October. It reduced accepted entries from 686 to 418 across these periods. This change is not an exit-price-only comparison: after a runner closes, an active fixed leg blocks new runners. The EA logged 481 / 470 / 334 / 256 “satellite remains after core” skipped signal attempts respectively; they are not necessarily unique missed fills.

The baseline had 45 observed 5R runners and the independent variant 22. The 5R counts exclude one end-of-test runner each in baseline August, September and October, and one each in independent September and October, because no exit MFE was recorded. These were different subsequent trade paths and sizes. The result gives a reason to investigate slot allocation; it does not prove that each missing large runner would be recoverable.

## What the existing minute closes show about retracements

The baseline's 23 runners reaching 5R in July and October were joined to the already exported M1 bars. For each, the analysis follows completed-minute closes from entry until the original exit. Long exits use bid closes; short exits use bid close plus the bar's recorded spread (0.01 point size), an approximation to ask at the close. The dates refer to broker-server time.

- After the first sampled close at or above 1R and before the first sampled close at or above 5R, **3 of 11 July** and **3 of 12 October** runners had a sampled close back at or beyond their entry.
- Over that same sampled interval, the largest close-to-close pullback from a prior sampled best was at least 1R in **9/11 July** and **7/12 October** runners; at least 2R in **5/11** and **4/12**.
- Median time between the first sampled 1R close and the first sampled 5R close was 132 minutes in July and 161 minutes in October. This is not the tick-level time between the actual 1R and 5R touches.

These are retrospective descriptions of only runners that eventually reached 5R under the original exit. “Before 5R” means before the **first M1 close** at 5R; price could have touched 5R earlier inside a minute. The data do not reveal the full intraminute path, and changing the stop would alter later positions. The counts are not an executable stop replay and cannot establish a winning stop distance. They do show why a tight 1R trail or immediate break-even could cut some later large runners.

## Next hypotheses, not established results

1. **Preserve fixed independence while reducing runner blockage.** Research a variant that lets a new runner open while an older fixed leg remains, only when direction and the combined risk budget permit it; keep at most one fixed leg and do not silently increase total modeled stop risk. The current experiment blocked new runners and materially reduced the number of observed large runs. This alternative has not been implemented or tested.
2. **Compare a wider runner trail with the existing M15 exit.** The close data suggests testing room for pullbacks rather than assuming a 1R trail survives, but it does not select 2R, 3R, or an activation point. A small, predeclared real-tick comparison must preserve a baseline, account for tick order, stop modification acceptance, gaps and the impact on later signals.
3. **Investigate the fixed leg separately.** Independent 1R did not reach the requested 55% in these periods. Changing to 1.5R or 2R requires full replay: a 1R target already closes its position and censors subsequent path, and a longer-held fixed leg changes slot occupancy and sizing.
4. **Check smaller nominal risk only through actual broker sizing.** The 3% runs have large drawdowns and minimum-volume/budget skips. Lowering risk requires real volume-step, min-lot, margin and risk-cap recalculation; do not scale these results linearly.

No candidate has established a reliable edge or a suitable live risk level. July–October are development data; freeze any chosen entry/exit/sizing rule before evaluating fresh unseen periods.

## Validation and files

The isolated source compiled with 0 errors and 0 warnings (source SHA-256 `8AD1377AE02F6544DDB14DDDB651A9231DFB68A24164EF65CB69E8FF8A71875E`, binary `312CF456682D64EB622BC537A9A99BB70BCD8A698A8191648CE9FB0663AA6E46`). Each MT5 report and closed-leg event ledger reconciled. Additional checks verified the mode was active, fixed exits were TP/SL/end-of-test only, fixed positions did not overlap, a new runner did not open while an earlier fixed leg remained, and requested fixed targets were 1R within tick rounding. The tests recorded 4 / 3 / 7 / 3 market-closed runner-close error events by month. These can delay exits.

The retracement CSV records each sampled path and its limitations. Original and independent trade counts differ because of position occupancy and dynamic sizing. All results are historical simulations, not live performance.
