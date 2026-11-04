# Simple Trender: M1 versus M3 signal on real ticks

Date: 2026-11-02. The user requested the same research configuration with the completed signal timeframe changed from M1 to M3. Both versions use the exact same research source and binary, USTECm, EMA(low)30 reclaim, smoothed VWAP17, completed M5 direction slope3, frozen M5 band stop, independent fixed 1R leg, M15 band/EMA210 runner exit, no staging, a fresh $1,000 deposit per month, nominal 3% total symbol stop risk with the EA's 90% sizing buffer, and leverage 1:2000. If a fixed leg remains after its runner exits, it blocks a new runner until it resolves.

MT5 model 4 real ticks was used. The tester chart is M1 for both variants, while `InpM5OnlySignalTf` changes from M1 to M3. The input sets and tester configurations were checked: apart from run identifiers and that signal-timeframe input, they match; source and binary files match exactly. The EA's existing history routine requests up to **1,800 M1 bars versus 1,200 M3 bars**, so the underlying warmup/history length in bars and elapsed time changes with the signal timeframe. This is inherent to the unchanged build and should be considered when interpreting the comparison.

## Month-by-month results

| Month | Accepted entries M1 → M3 | Fixed 1R hits M3 | Runner net M3 | Fixed net M3 | Combined net M1 → M3 | Relative equity DD M1 → M3 | M3 PF |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| July | 101 → 93 | 56/93 (60.2%) | +$90.39 | +$195.12 | −$20.04 → +$285.51 | 31.52% → 26.70% | 1.19 |
| August | 109 → 91 | 46/90 (51.1%) | −$181.44 | +$32.13 | −$228.58 → −$149.31 | 37.79% → 43.44% | 0.89 |
| September | 110 → 91 | 44/91 (48.4%) | +$54.59 | −$74.86 | +$99.59 → −$20.27 | 24.12% → 25.35% | 0.98 |
| October 1–25 | 98 → 86 | 45/86 (52.3%) | +$227.81 | +$8.46 | −$44.85 → +$236.27 | 29.20% → 30.04% | 1.20 |

Fixed hit rate counts TP divided by TP or SL resolutions; the one August M3 fixed position closed at the end of the test is excluded from that denominator, while its cash result is included in net. Across the four periods M3 had 191/360 fixed TP/SL resolutions (53.1%), compared with 213/416 (51.2%) for M1. These are descriptive pooled counts from separate monthly accounts and are not proof of a 55% edge.

M3 had 361 accepted signals over 117 calendar days, or 3.09/day on average; M1 had 418, or 3.57/day. This is an average across the selected periods, not a claim of 3–5 entries every day. Changing timeframe also changes which signals arise, fixed-slot occupancy, equity and future sizing. Net dollar balances of these independent accounts must not be added and presented as a portfolio return.

## M3 runner excursion

| Month | Runner legs | Measured for MFE | ≥5R peak | ≥10R peak | ≥15R peak | Median MFE | Median giveback | Largest runner net |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| July | 61 | 61 | 6 | 5 | 1 | 1.12R | 1.50R | +$139.29 |
| August | 63 | 62 | 5 | 3 | 3 | 0.90R | 1.30R | +$246.82 |
| September | 64 | 64 | 5 | 2 | 1 | 0.54R | 1.34R | +$234.41 |
| October 1–25 | 48 | 48 | 10 | 3 | 1 | 0.59R | 1.28R | +$212.15 |

The thresholds overlap: a 15R runner is also counted at 10R and 5R. One August end-of-test runner has no logged exit MFE and is excluded. Across measured M3 runners, 26 reached 5R, 13 reached 10R, and 6 reached 15R. These are maximum favorable excursions, not exit profits.

## Reading the result

M3 improved July and October net versus the directly comparable M1 independent-exit runs. August lost less in cash but had a higher peak-to-trough percentage drawdown; September changed from a profit to a small loss. The pooled fixed hit rate increased by about 1.9 percentage points, but was below 55% and monthly results varied. M3 produced more observed 5R runners in this specific comparison (26 versus 22), while producing fewer accepted entries overall; the two variants have different position paths.

These periods have been used repeatedly for research and cannot validate a newly selected timeframe out of sample. A higher return in a few months is not evidence of a dependable edge. At the tested 3% nominal risk, M3's 25%–43% reported equity drawdowns remain material. Real-tick historical simulations still do not guarantee live execution.

## Audit

The July/August/September/October M3 reports each stated 100% real-tick history and recorded 7,996,333 / 17,284,128 / 25,779,944 / 29,608,040 ticks. All 154 / 154 / 155 / 134 closed legs reconciled to their reports and event ledgers. Additional checks verified independent-fixed mode, TP/SL/end-of-test-only fixed exits, the requested 1R target within tick rounding, no overlap of fixed legs, and no new runner while an earlier fixed leg remained. The M3 runs recorded 6 / 0 / 7 / 1 market-closed runner-close error events, which can delay intended exits.

Research source SHA-256: `8AD1377AE02F6544DDB14DDDB651A9231DFB68A24164EF65CB69E8FF8A71875E`; compiled binary SHA-256: `312CF456682D64EB622BC537A9A99BB70BCD8A698A8191648CE9FB0663AA6E46`. The separate research build and archives are supplied; the canonical project EA was not changed.
