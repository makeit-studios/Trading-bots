# USTECm M1, M5 and M15 bars, 2026-01-01 through 2026-11-03

These three semicolon-delimited UTF-8 CSVs were generated from Exness-MT5Trial9 broker history by `Experts/TrenderBarExport.mq5` in an isolated MT5 tester. The tester ran on an M1 chart from `2026.01.01` to `2026.11.04` with model 2 (open prices only). The 2026-11-04 tester end date is exclusive. The export source also emits M3 bars; those and four rows outside the requested dates were removed during preparation. No price values or spreads were synthesized by the preparation step.

| File | Rows | First bar time | Last closed bar time | Size |
| --- | ---: | --- | --- | ---: |
| `USTECm_M1_2026-01-01_to_2026-11-03.csv` | 298,758 | 2026-01-01 23:00 | 2026-11-03 23:58 | 19,670,593 bytes |
| `USTECm_M5_2026-01-01_to_2026-11-03.csv` | 59,753 | 2026-01-01 23:00 | 2026-11-03 23:50 | 3,974,287 bytes |
| `USTECm_M15_2026-01-01_to_2026-11-03.csv` | 19,931 | 2026-01-01 23:00 | 2026-11-03 23:30 | 1,357,119 bytes |

Header: `tf;time;open;high;low;close;tick_volume;spread_points;real_volume`. `tf` is the timeframe in minutes. `time` is the broker bar-open timestamp. `spread_points` is the integer broker-point spread stored in each MT5 `MqlRates` bar; it is not a price-unit value or a bid/ask tick series. All exported rows have a nonzero spread. The last listed bars are the last bars that had closed before the tester ended, so the final incomplete bar of November 3 is absent where applicable.

The MT5 report stated **100% history quality for model 2**, with 298,759 M1 tester bars and 1,195,034 generated tester ticks. That label does **not** mean 100% real ticks. The tester produced zero trades. Validation checked the date range, all eleven calendar months, strictly increasing unique bar times per timeframe, OHLC geometry, positive tick volume, and nonnegative spread. `manifest.json` records monthly row counts, spread bounds and SHA-256 hashes for the files and exporter source.
