# Simple Trender timeframe and period quick screen

Date: 2026-10-29. This is a development screen, not an out-of-sample result or a live-trading recommendation.

## Rules tested

- Closed M1, M3, or M5 Simple Trender arrow; latest completed M5 band direction must agree. M15 is **not** an entry filter. The frozen protective stop is one broker tick outside the latest completed M5 outer band. The initial comparison uses a fixed 1R target. A separate runner check uses the existing M15 band/major-EMA exit and repeat 1R slot.
- The original indicator periods are EMA(low) 26, VWAP smoothing 13, and EMA(close) 200. There is no slow 50-period input in the supplied Simple Trender. The fixed 1R entry/exit does not use the major EMA, so changing 190/200/210 only affects runner exits.
- Bundled profiles: base 26/13/3, fast 23/11/2, smooth 30/15/4, where the final number is completed M5 slope bars. One-factor screens also varied EMA(low) to 23/30, VWAP smoothing to 11/15, and slope bars to 2/4 individually.
- All MT5 runs use Exness demo XAUUSDm, BTCUSDm, EURUSDm, and USTECm, $10,000 USD hedging account, 0.5% planned stop risk per symbol (split between runner and 1R leg), and **open prices only** (tester model 2). The EA was compiled with zero errors and warnings.

## Method and limits

The fast local screen reads M1/M3/M5/M15 bars exported by MT5 using the open-price model. It simulates bid/ask spread, a one-tick M5-band stop, 1R targets, and conservative stop-first ordering when a minute bar touches both stop and target. It omits broker lot-step and execution details, so it is a ranking tool. Candidate counts and wins were checked in MT5; the audited MT5 event ledgers reconcile with each tester report. MT5 itself warns that open-price testing may trigger stops and targets at prices different from requested levels. [MetaQuotes tester tick models](https://www.mql5.com/en/book/automation/tester/tester_ticks).

The broad screen compared July 8–31 and October 12–25 after seven or more days of indicator warmup. Selected settings were then checked on full July 1–31 and October 1–25 MT5 windows. July and October have informed rule selection throughout this project; August and September remain untouched. Each MT5 run starts a separate $10,000 account. Net dollar amounts below are per run and must not be added as a portfolio balance.

## MT5 fixed 1R results

| Symbol / setting | Window | Trades | Wins | Win rate | Expectancy | Net | Profit factor |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| BTC M3 arrow, M5 direction, 23/11/2 | Full July | 15 | 9 | 60.0% | +0.200R | +$137.44 | 1.51 |
| BTC M3 arrow, M5 direction, 23/11/2 | Full October | 14 | 7 | 50.0% | 0.000R | -$1.34 | 1.00 |
| USTEC M1 arrow, M5 direction, 30/13/3 | Full July | 14 | 6 | 42.9% | -0.143R | -$86.56 | 0.76 |
| USTEC M1 arrow, M5 direction, 30/13/3 | Full October | 14 | 10 | 71.4% | +0.429R | +$270.94 | 2.49 |
| Gold M1 arrow, M5 direction, 23/11/2 | July 8–31 | 9 | 2 | 22.2% | -0.558R | -$199.95 | 0.30 |
| Gold M1 arrow, M5 direction, 23/11/2 | October 12–25 | 5 | 4 | 80.0% | +0.600R | +$129.60 | 4.00 |
| EUR M5 arrow, M5 direction, 26/13/3 | October 12–25 | 15 | 5 | 33.3% | -0.280R | -$183.05 | 0.55 |

The BTC M3 setting with only VWAP smoothing changed to 11 (26/11/3) produced 15 trades, 53.3% wins, and +$46.14 in the July slice; 10 trades, 70.0% wins, and +$178.43 in the October slice. It has more trades than the bundled fast setting but a weaker July result. USTEC's 30/13/3 setting performs similarly to the bundled smooth setting, so the single EMA(low) change is the simpler candidate. Gold's October improvement reverses sharply in July. All nine EURUSD timeframe/profile combinations in the October local screen had negative fixed 1R expectancy.

## Runner and major EMA

| Setting | Window | Unique entries / completed legs | Fixed-leg win rate | All-leg expectancy | Net | Equity drawdown | Runner median MFE / giveback |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| USTEC M1, 30/13/3, major EMA210 | Full July | 17 / 33 | 52.9% | +0.429R | +$317.84 | 2.83% | 0.704R / 1.702R |
| USTEC M1, 30/13/3, major EMA210 | Full October | 14 / 26 | 64.3% | +1.119R | +$659.40 | 1.80% | 2.242R / 1.534R |
| BTC M3, 23/11/2, major EMA200 | July 8–31 | 11 / 21 | 63.6% | +0.429R | +$200.41 | 3.25% | 1.675R / 1.832R |
| BTC M3, 23/11/2, major EMA200 | October 12–25 | 8 / 15 | 50.0% | -0.349R | -$115.62 | 1.76% | 0.012R / 1.000R |

On the shorter October **smooth** USTEC runner comparison, major EMA190/200/210 produced +$406.73 / +$403.57 / +$508.80. On BTC M5 smooth, the same major EMA values produced +$105.92 / +$105.92 / +$58.42. Thus 210 is not a general improvement. The full-month USTEC EMA30 runner was tested at 210; its full-month 190/200 alternatives were not tested in MT5.

## Decision

The two leading research candidates are BTC M3 with 23/11/2 and USTEC M1 with 30/13/3, both with M5 direction and M5 stops. The BTC fixed edge weakens to flat in full October; its runner loses in the October slice. USTEC's runner stays positive in both full development months, but its fixed leg misses the 55–60% target in July and the median runner gives back more than 1.5R. Together, BTC fixed and USTEC runner produced 32 unique entries in 31 July days and 28 in 25 October days: about 1.0–1.1 entries per calendar day, below the 3–5 target. These results do not justify calling the system viable yet.

This screen deliberately held the M5 stop constant. The earlier real-tick M3-versus-M5 stop comparison is in `local_tester/reports/trender_runner_dev_m1m5_stops_oct_20261028`; the partially run July real-tick matrix was stopped when the quick screen was requested. Before another parameter search, verify the two candidates on real ticks and on dates not used to choose them, with the exact same rules and no further tuning.

Key artifacts:

- `local_tester/reports/trender_bars_quick_jul_20261029/screen_onefactor_jul.csv`
- `local_tester/reports/trender_bars_quick_oct_20261028/screen_onefactor_oct.csv`
- `local_tester/reports/trender_quick_full_ustec_ema30_runner210_jul_20261029`
- `local_tester/reports/trender_quick_full_ustec_ema30_runner210_oct_20261029`
- `local_tester/reports/trender_quick_full_btc_m3_fast_fixed_jul_20261029`
- `local_tester/reports/trender_quick_full_btc_m3_fast_fixed_oct_20261029`
