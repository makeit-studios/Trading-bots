# Simple Trender: M5 and M15 entry signals on real ticks

Research date: 2026-11-02. Eight new USTECm MT5 model-4 tests use the same independent fixed-leg configuration as the previous M1/M3 tests. Each symbol/month/timeframe starts a separate $1,000 account at 1:2000 leverage with 3% nominal combined stop risk and the EA's 90% sizing buffer. October is October 1–25.

The entry is EMA(low)30 reclaim with smoothed VWAP17 on the selected completed signal timeframe. Direction and original stop are from the latest completed M5 band, with slope3; the fixed leg has its own 1R TP and SL and is not closed by the M15 runner exit. The runner uses the existing M15 band / EMA210 exit. A fixed leg remaining after a runner exit prevents another runner from opening until the fixed leg resolves. No runner trail, staging, RSI, efficiency gate or retuning was introduced.

The tester chart remains M1 for all variants to process ticks; only the signal timeframe input differs. M5 uses the existing research EA binary. M15 required a research-only extension permitting M15 and maintaining a distinct M15 signal-bar clock so it does not interfere with the runner's M15 exit clock. Source diff review confirms only M15 support was added. The M15 candle supplies the entry signal; M5 still supplies entry direction and the stop. Input sets and tester configurations match the M1 controls apart from the signal timeframe and unique run identifiers.

## Monthly results

| Month | M5 entries | M5 fixed 1R hits | M5 total net | M5 equity DD | M15 entries | M15 fixed 1R hits | M15 total net | M15 equity DD |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| July | 70 | 41/70 (58.6%) | +$268.03 | 23.39% | 44 | 30/44 (68.2%) | +$206.84 | 23.53% |
| August | 80 | 40/80 (50.0%) | −$99.29 | 35.92% | 48 | 25/48 (52.1%) | +$181.81 | 15.17% |
| September | 91 | 48/91 (52.7%) | +$392.64 | 32.36% | 41 | 25/41 (61.0%) | +$145.88 | 14.16% |
| October 1–25 | 80 | 47/80 (58.8%) | +$346.76 | 26.10% | 38 | 24/37 (64.9%) | +$182.51 | 18.10% |

Fixed hit rate is take-profit exits divided by TP/SL resolutions. One M15 fixed leg closed at the October end of test is excluded from that denominator but included in net. Across these separate monthly runs, M5 had **176/321 (54.8%)** TP hits and M15 **104/170 (61.2%)**. The M15 aggregate exceeds the 55% screen, but August did not, the samples are modest, and these months have been used repeatedly for development.

M5 generated 321 accepted entries over 117 calendar days (**2.74/day**), while M15 generated 171 (**1.46/day**). These are averages, not a guarantee on individual days. The original goal was 3–5 unique entries/day across the selected portfolio; these standalone USTEC results are below that average. M1 and M3 independent-fixed controls had 418 (3.57/day) and 361 (3.09/day) entries respectively. Separate monthly account results are not a combined portfolio return.

## Runner results

| Period | M5 runner net | M5 runner peak ≥5R / ≥10R / ≥15R | M15 runner net | M15 runner peak ≥5R / ≥10R / ≥15R |
| --- | ---: | ---: | ---: | ---: |
| July | +$111.90 | 6 / 5 / 2 | −$25.89 | 3 / 2 / 1 |
| August | −$64.05 | 4 / 2 / 1 | +$167.07 | 2 / 2 / 1 |
| September | +$326.04 | 9 / 5 / 1 | +$20.46 | 5 / 2 / 1 |
| October 1–25 | +$139.20 | 9 / 5 / 2 | +$24.68 | 4 / 2 / 1 |

Thresholds overlap; maximum favorable excursion is a peak and not realized net profit. M15 had one end-of-test runner without logged exit MFE in October, excluded from its peak counts. The largest M5 September runner made +$479.89, more than that month's +$392.64 combined net; M15 August's largest runner made +$241.83 versus +$181.81 combined. These examples show concentration in a few trades.

## Interpretation

M15 is a promising candidate in this sample: positive combined net in all four months, a 61.2% pooled fixed target-hit rate, and lower reported drawdowns than M5 in these particular tests. It also produced substantially fewer entries and missed the pooled 55% screen in August. M5 came just below 55% pooled and lost in August. These are development observations, not evidence that M15 is reliably profitable or that it meets the entry-frequency goal.

The EA's unchanged history routine requests up to 1,800 bars for the M5 signal and 1,200 bars for M15. Thus warmup history in bars and elapsed time changes with signal timeframe, as it did in the M1/M3 comparison. A new, untouched period is required to test a frozen candidate after reviewing these development results. The 3% nominal-risk tests still experienced material drawdowns, and real-tick historical results do not guarantee live fills.

## Audit and execution limitations

All eight new reports stated **100% real ticks**, with positive bars and tick counts. Closed trade/event ledgers reconciled to MT5 reports: M5 had 121 / 138 / 149 / 127 closed legs; M15 had 79 / 84 / 79 / 66. Additional checks verified fixed exits were TP, SL or end-of-test only, no overlapping fixed positions, no new runner while an earlier fixed position remained, 1R requested target geometry, the selected signal timeframe, and that each logged signal and frozen M5 stop used a completed bar.

Runner-close attempts rejected with MT5 market-closed code 10018 numbered **4 / 6 / 7 / 0** for M5 and **3 / 0 / 3 / 0** for M15. Later outcomes are reflected in the reconciled reports, but the rejection can delay an intended close.

The M5 source SHA-256 is `8AD1377AE02F6544DDB14DDDB651A9231DFB68A24164EF65CB69E8FF8A71875E`; binary `312CF456682D64EB622BC537A9A99BB70BCD8A698A8191648CE9FB0663AA6E46`. M15 source SHA-256 is `29194A34C36BB201279A1B04D57F802AD4B350D6051AD565B36C5EF65B26CBF2`; binary `BEEE959D26D1A2C113BE340D11972FF8F2D3A68EC591E3884AD620EECFFF20C7`. The M15 research source compiled with 0 errors and 0 warnings. The canonical active project EA was not changed.
