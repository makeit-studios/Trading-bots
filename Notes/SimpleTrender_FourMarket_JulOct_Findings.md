# Simple Trender four-market checkpoint

Date: 2026-10-27. **Paused after July at the user's request. August and September have not been run.** These are separate one-symbol Strategy Tester experiments, not a ranked four-symbol portfolio result or a live-trading recommendation.

## Fixed test setup

- Broker: Exness-MT5Trial9 demo history; MT5 Strategy Tester, M15, requested real-tick model 4. Every completed report below confirms **100% real ticks**.
- Each run starts from USD 10,000, leverage 1:2000. July = 2026-07-01 to 2026-08-01 exclusive; October = 2026-10-01 to 2026-10-26 exclusive.
- Mode 0: closed M15 Simple Trender arrow with a 0.50 ATR band-distance limit. Mode 1: identical entry but only when the H4 scan qualifies and direction agrees. The H4 scan uses 12-bar efficiency ratio >=0.45, net move >=1.5 H4 ATR14, and two closed H4 closes on the directional side of EMA(low,26).
- Both modes use the same stop entry beyond the signal candle, opposite-candle stop, 2R target, maximum spread/stop distance 0.10, 0.5% nominal equity risk with a 10% sizing reserve, round-down lots, and **broker-side expiry after two M15 candles**.
- The audited EA was compiled with zero errors and zero warnings. The July and October trade ledgers reconcile exactly to each tester report; the order-time audit found **zero fills after expiry**. The earlier `trender_market_oct2026_20261027` batch had 51 late fills from an EA bug and is excluded from every result below.

## Realized results

Each cell is `completed trades / net USD / max relative equity drawdown`. The account restarts at $10,000 in each cell; do not add the cells to infer portfolio performance.

| Market | July arrow only | July H4 + arrow | October arrow only | October H4 + arrow |
| --- | ---: | ---: | ---: | ---: |
| Gold `XAUUSDm` | 34 / −65.16 / 5.04% | 4 / −166.05 / 1.66% | 31 / +182.36 / 2.25% | 3 / −123.89 / 1.24% |
| BTC `BTCUSDm` | 43 / −98.01 / 5.76% | 7 / −50.86 / 2.39% | 35 / +273.39 / 3.04% | 4 / +221.53 / 0.74% |
| FX `EURUSDm` | 9 / −143.42 / 2.95% | 1 / −44.55 / 0.45% | 13 / +81.76 / 2.06% | 1 / −44.65 / 0.60% |
| NASDAQ proxy `USTECm` | 30 / −178.63 / 5.41% | 4 / −186.23 / 1.88% | 29 / +147.49 / 3.46% | 5 / +40.92 / 1.37% |

The arrow-only version was negative in July and positive in October on **all four** markets. The specified H4 gate produced only 1–7 filled trades per market per month. Gold's seven filtered trades all lost; EURUSD had two filtered losses; BTC and USTEC changed sign across the months. No market or filter has shown stable positive performance here. In July, the H4 scan marked 15/142 to 43/186 closed H4 bars eligible across the four markets; in October, 14/106 to 33/150. The subsequent M15 direction and execution gates shrink that to the small fill counts in the table.

## Audit files

- October corrected ten-symbol screen: `local_tester/reports/trender_market_oct_fixed_20261027/summary.csv`, `trades.csv`, `event_counts.csv`, `skip_reasons.csv`, `late_fills.csv`, and individual tester HTML reports with graphs.
- July gold/EURUSD and completed extra screens: `local_tester/reports/trender_market_jul26f/`. The original ten-symbol July sequence was stopped after US30; its `status.txt` explains the partial scope.
- July BTC/USTEC: `local_tester/reports/trender_market_jul26focus/` with the same audit files.
- The scripts `local_tester/run_trender_market_research.ps1` and `local_tester/analyze_trender_market.py` reproduce the run settings and extract each closed trade and skipped-signal count.

## Rule changes to discuss before August

1. Keep broker-side expiry, stop/risk sizing, and the spread guard. They prevent the exact stale-order error found in the first batch and make execution costs visible.
2. The H4 trend definition is too selective to judge with these two months. A **new, labeled candidate** could replace it with: H4 close on the directional side of EMA(low,26), EMA(low,26) sloping in that direction over three completed H4 bars, 12-bar efficiency ratio >=0.30, and net 12-bar move >=1.0 H4 ATR14. This is a proposed diagnostic variant, not a validated improvement. Compare it with the existing gate using identical M15 entries and exits.
3. The Pine script's initial-entry bar change and its pullback arrow are different triggers. If the H4 test still has too few trades, compare the first closed M15 bar crossing to the H4 trend side of EMA(low,26) with the closed pullback arrow. Do not mix this entry change with the H4 threshold change in one test.
4. Keep August and September untouched until the rule changes are agreed and frozen. All July/October observations and the screenshot review are design data; no earlier month should be called a clean holdout.
