# Simple Trender: randomly selected 2024–2025 months

This is one continuous $1,000 USTECm account tested from January 1, 2024 through December 31, 2025. New entries were permitted only in the four randomly drawn months below. Existing positions retained their usual stops, targets and runner exits during intervening months.

The six-year month draw was locked at 2026-11-04T02:26:41.037230+00:00 using Python secrets.SystemRandom.sample(range(1, 13), 2), sorted; no redraw.

The original six-year draw also selected February/April 2020, July/August 2021, May/July 2022, and August/September 2023. Those eight months were not tested because this Exness profile lacked usable minute history before January 2024. The 2024–2025 result is an approximation, as the profile supplied no real USTECm ticks before January 2026. MT5 model 2 uses open prices only. MT5 reported 98% history quality, so bar-history quality was imperfect; the score does not indicate real ticks.

## Combined account result

| Entries | Net | Final balance | Profit factor | Maximum relative equity drawdown | 1R TP / TP+SL | 2R TP / TP+SL |
|---:|---:|---:|---:|---:|---:|---:|
| 168 | -$534.84 | $465.16 | 0.70 | 64.54% (746.71) | 69/156 | 44/143 |

Leg net: runner -$265.66; 1R fixed -$159.02; 2R fixed -$110.16. MT5 processed 702866 bars and 2811314 generated ticks; reported history quality was 98%. There were 33 rollback starts and 6 logged close errors.

## Drawn months

Net is attributed to the month in which a position opened; it includes the full result of any position that closed in a later month.

| Entry month | Opening balance | Unique entries | Three-leg sets | 1R TP / TP+SL | 2R TP / TP+SL | Runner net | All-leg net |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2024-03 | $1,000.00 | 51 | 38 | 16/42 | 11/39 | -$117.87 | -$283.14 |
| 2024-08 | $716.86 | 35 | 31 | 11/33 | 8/32 | -$71.22 | -$186.68 |
| 2025-08 | $530.18 | 49 | 42 | 24/48 | 15/42 | -$68.72 | -$66.48 |
| 2025-11 | $463.70 | 33 | 30 | 18/33 | 10/30 | -$7.85 | $1.46 |

## Method and limits

The existing M15 three-leg research rules used EMA(low)30, smoothed VWAP17, completed M5 direction/slope3, a frozen M5 band stop, independent 1R and 2R fixed legs, and the M15 band/EMA210 runner exit. Nominal risk was 3% of current equity with the EA's 90% sizing reserve, targeting at most 2.7% combined entry-to-stop risk before execution effects. The tester used 1:2000 leverage. The original 2026 year-to-date real-tick test is a different time sample and should not be combined as one account.

The only EA rule change was an entry-month filter. The month draw was saved before any test results were inspected. The research source, tester script, inputs, MT5 report, event ledger, reconciled trades and tier-safety audit were archived. The compiled EA's SHA-256 is recorded in the run manifest. Open-prices-only fills and missing earlier years prevent this result from establishing a live-trading edge.

Research source SHA-256: `1F82E21E7ED13E7AD6DA744B2B0BF90D49956B608BF603033945645D88EB9387`.
