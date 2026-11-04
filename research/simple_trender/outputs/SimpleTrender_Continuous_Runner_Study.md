# Simple Trender: continuous real-tick runner exit study

Each row starts its own $1,000 account and runs continuously from July 1 through October 25, 2026. USTECm, real ticks, fixed 1R leg, M5 band initial stop, 3% nominal combined equity risk with the existing 90% sizing reserve, and M15 runner exit remain in effect. Returns are development-sample results, not out-of-sample evidence.

| Signal | Runner management | Entries | Net | Profit factor | Maximum equity drawdown | Fixed net | Runner net | Runner mean net R | 5R / 10R / 15R peaks |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| M5 | baseline | 316 | $1234.37 | 1.25 | 52.45% (837.98) | $618.80 | $615.57 | 0.262 | 27 / 17 / 6 |
| M5 | break-even | 319 | $1444.27 | 1.29 | 50.58% (844.08) | $675.28 | $768.99 | 0.273 | 22 / 14 / 6 |
| M5 | break-even + ATR | 323 | $375.77 | 1.09 | 54.84% (829.74) | $378.74 | $-2.97 | 0.037 | 23 / 8 / 3 |
| M15 | baseline | 171 | $937.90 | 1.33 | 23.68% (380.19) | $689.86 | $248.04 | 0.144 | 14 / 8 / 4 |
| M15 | break-even | 173 | $679.54 | 1.29 | 22.01% (314.85) | $604.95 | $74.59 | 0.058 | 9 / 4 / 3 |
| M15 | break-even + ATR | 174 | $736.70 | 1.32 | 21.07% (276.01) | $630.56 | $106.14 | 0.063 | 9 / 4 / 2 |

Runner net R and MFE counts exclude positions forced closed at the end of the test because their MFE was not logged; cash totals include them. The 5R, 10R and 15R peak counts overlap and are not realized profit. Trade paths, position sizes, and accepted signals can differ between variants. Each stop-trigger and stop-modification event was checked against the original position risk and direction.

## Monthly account snapshots

Snapshots are taken on the first available tick of each broker-server month, before processing that tick. Open positions carry across month boundaries. Realized trade net is attributed to the month of the final exit and includes the full trade’s entry costs; it is not the change in month-end equity. October ends on October 25.

| Signal | Management | Month | First-tick balance | First-tick equity | Open positions | Trade net closed in month |
|---|---|---|---:|---:|---:|---:|
| M5 | baseline | 202607 | $1000.00 | $1000.00 | 0 | $268.03 |
| M5 | baseline | 202608 | $1268.03 | $1268.03 | 0 | $-182.87 |
| M5 | baseline | 202609 | $1085.16 | $1085.16 | 0 | $394.49 |
| M5 | baseline | 202610 | $1479.65 | $1479.65 | 0 | $754.72 |
| M5 | break-even | 202607 | $1000.00 | $1000.00 | 0 | $325.09 |
| M5 | break-even | 202608 | $1325.09 | $1325.09 | 0 | $-197.86 |
| M5 | break-even | 202609 | $1127.23 | $1127.23 | 0 | $443.90 |
| M5 | break-even | 202610 | $1571.13 | $1571.13 | 0 | $873.14 |
| M5 | break-even + ATR | 202607 | $1000.00 | $1000.00 | 0 | $242.96 |
| M5 | break-even + ATR | 202608 | $1242.96 | $1242.96 | 0 | $-347.24 |
| M5 | break-even + ATR | 202609 | $895.72 | $895.72 | 0 | $66.26 |
| M5 | break-even + ATR | 202610 | $961.98 | $961.98 | 0 | $413.79 |
| M15 | baseline | 202607 | $1000.00 | $1000.00 | 0 | $206.84 |
| M15 | baseline | 202608 | $1206.84 | $1206.84 | 0 | $221.88 |
| M15 | baseline | 202609 | $1428.72 | $1428.72 | 0 | $208.14 |
| M15 | baseline | 202610 | $1636.86 | $1636.86 | 0 | $301.04 |
| M15 | break-even | 202607 | $1000.00 | $1000.00 | 0 | $59.49 |
| M15 | break-even | 202608 | $1059.49 | $1059.49 | 0 | $213.67 |
| M15 | break-even | 202609 | $1273.16 | $1273.16 | 0 | $166.03 |
| M15 | break-even | 202610 | $1439.19 | $1439.19 | 0 | $240.35 |
| M15 | break-even + ATR | 202607 | $1000.00 | $1000.00 | 0 | $71.80 |
| M15 | break-even + ATR | 202608 | $1071.80 | $1071.80 | 0 | $90.79 |
| M15 | break-even + ATR | 202609 | $1162.59 | $1162.59 | 0 | $290.11 |
| M15 | break-even + ATR | 202610 | $1452.70 | $1452.70 | 0 | $284.00 |

## Execution observations

| Signal | Management | BE triggers | Trail triggers | Accepted stop changes | Stop rejections | Market-closed stop rejections | Deferred invalid stops | Close errors | Minimum-volume skips |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| M5 | baseline | 0 | 0 | 0 | 0 | 0 | 0 | 17 | 3 |
| M5 | break-even | 67 | 0 | 67 | 0 | 0 | 0 | 17 | 3 |
| M5 | break-even + ATR | 69 | 23 | 228 | 2620 | 2620 | 13 | 17 | 10 |
| M15 | baseline | 0 | 0 | 0 | 0 | 0 | 0 | 6 | 0 |
| M15 | break-even | 50 | 0 | 50 | 0 | 0 | 0 | 6 | 2 |
| M15 | break-even + ATR | 51 | 9 | 126 | 381 | 381 | 12 | 6 | 2 |

Break-even is entry price, not guaranteed net zero after spread, commission, swap, gaps or slippage. Trailing updates use M15 ATR(14) from the last completed candle and completed M15 candles entirely after entry; an entry-bar partial candle is excluded to avoid using pre-entry highs or lows. Stop changes use broker tick-size, stop-distance and freeze checks. Rejected or invalid changes retain the last accepted stop.

The M15 trail run used an earlier build. Its deferred-stop events were audited: every affected position already had an accepted stop at or beyond break-even, so the later fallback change could not alter those events. Rejection counts are attempts, not unique positions. Historical spreads and simulated fills do not guarantee live execution. The existing entry-to-stop risk calculation is scoped to matching positions, not total account exposure.

All completed reports stated 100% real-tick history and reconciled against the trade/event ledger. The M15 baseline, break-even and trail rules and the M5 rules were chosen using these development months. Freeze any future candidate before evaluation on a genuinely unseen period.
