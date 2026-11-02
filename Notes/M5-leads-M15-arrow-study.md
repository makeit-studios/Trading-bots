# M5 leading M15 Simple Trender arrows

Research replays: Exness demo `XAUUSDm`, 1–30 July 2026 (6,024 M5 bars, 6,496,004 ticks) and 1–22 October 2026 (4,416 M5 bars, 4,135,503 ticks). Both tester reports show 100% real ticks. This is a timing study; the probe never sends orders and these counts do not establish profitability.

The probe runs the same EMA-low(26) and EMA-of-session-VWAP(13) approximation used by `LiveArrowM5EA` on both M5 and M15. It records the first tick showing each arrow and evaluates the final arrow only after the bar closes. At an M5 event, the M15 band state comes from the **last closed M15 bar** (`close` versus EMA-low). No future M15 data is used to qualify the candidate. The broker's daily tick-volume VWAP may differ from TradingView's VWAP in the screenshots.

The `Pics/Trend` screenshots include XAGUSD M5/M15/H1 and XAUUSD M5 examples. They show where historical arrows ended up, but a still image cannot show when a live arrow first appeared or whether it disappeared. The real-tick probe addresses that timing question on the requested gold M5/M15 pair.

| Observation | July | October |
| --- | ---: | ---: |
| M5 first-sight arrows | 374 | 308 |
| Those still present at M5 close | 179 (48%) | 146 (47%) |
| M15 first-sight arrows | 201 | 172 |
| Those still present at M15 close | 97 (48%) | 86 (50%) |
| First M5 arrow per M15 candle and direction | 289 | 238 |
| Of those, last closed M15 band aligned | 157 | 109 |
| Aligned M5 events that preceded a same-direction live M15 arrow in that M15 candle | 63 | 22 |
| Those lead events with an M15 arrow that remained at M15 close | 35 | 12 |
| Aligned M5 events with no same-direction M15 live arrow in that M15 candle | 70 | 62 |

For aligned M5 events that led a same-direction live M15 arrow, the median lead to the live arrow was **10 seconds in July** and **23 seconds in October**. For those that ultimately confirmed on M15, the median wait from M5 first sight to M15 candle close was **13.4 minutes** in each window. Of all M15 live arrows, 63 of 201 in July and 22 of 172 in October had an earlier same-direction M5 event in the same M15 candle with the last closed M15 band aligned.

Interpretation: waiting for a live M15 arrow adds little time in the subset where both live arrows appear. Requiring that arrow mainly **removes setups**: 70 of 157 aligned early M5 events in July and 62 of 109 in October had no same-direction M15 live arrow in their candle. Some may still be valid continuation trades because the M15 arrow is a pullback crossing signal, not a persistent trend state. The high rate of disappearing live arrows makes a first-sight rule materially different from an M5-close rule. The July-to-October difference in lead counts also cautions against inferring a fixed edge from arrow timing alone.

The practical next comparison is to keep the existing M5 first-sight entry and fixed stop/1:1–1:2 target, then test one fixed filter: the last closed M15 band must agree with the M5 arrow. A separate M5-closed-arrow run is a timing benchmark. Compare trade count, expectancy, drawdown, and skip reasons on development and holdout dates before selecting a live rule. Do not make a live M15 arrow mandatory solely because it resembles the historical screenshots.

Artifacts: `Experts/ArrowLeadProbe.mq5`, `local_tester/run_arrow_lead_probe.ps1`, `local_tester/summarize_arrow_lead.ps1`, and `events.csv` plus the tester report in each of `local_tester/reports/arrow_lead_20261024_055537` (July) and `arrow_lead_20261024_055309` (October).
