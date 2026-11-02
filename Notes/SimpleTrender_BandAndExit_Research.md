# Simple Trender band-width and runner-exit research

Date: 2026-10-28. Status: research only; no trading rule or EA change is authorized by this note.

## Current evidence

The current runner test requires a confirmed higher-high/higher-low or lower-high/lower-low pattern on both the selected higher timeframe and M15. Each pivot needs two completed bars on its right. In the completed July runs this rejected most closed M5 arrows:

| Symbol/filter | Closed M5 arrows | Rejected by structure | Accepted | Fixed 1R win rate |
| --- | ---: | ---: | ---: | ---: |
| XAUUSDm H1 | 183 | 174 | 4.9% | 33.3% (6 trades) |
| XAUUSDm H4 | 183 | 171 | 6.6% | 44.4% (9 trades) |
| BTCUSDm H1 | 288 | 266 | 7.6% | 41.2% (17 trades) |
| BTCUSDm H4 | 288 | 260 | 9.7% | 32.0% (25 trades) |
| EURUSDm H1 | 236 | 225 | 4.7% | 40.0% (10 trades) |

The one-R legs therefore failed to reach the 50% pre-cost break-even rate in this development month. The structure gate reduced frequency without producing a high win rate. These are small, selected development samples, so they are evidence against the current rule rather than a final strategy verdict.

The runner exits also need revision. July runner win rates ranged from 4.5% to 22.2%. Average maximum favorable excursion was 1.13R to 3.51R, but average giveback before exit was 1.73R to 2.34R. A BTC H1 outlier reached 43.38R MFE and still gave back 8.71R. This confirms that the first M15 structure break can be a local pullback inside a continuing higher-timeframe trend and is too sensitive to serve as the only runner exit.

## What the screenshots show

The blue line is EMA(close, 200). The original Pine source plots it but does not use it in the arrow expression. Its comments propose exiting on the first close across EMA(low, 26), not on EMA200. Using EMA200 as an exit is therefore a new test rule.

The screenshots show three recurring states:

1. During clean directional moves, EMA(low, 26) and smoothed VWAP separate and the shaded band widens.
2. Near pauses and consolidations, the two lines converge and the band contracts.
3. A local M15 structure break can happen while the broader band and EMA200 regime remain intact, after which the trend can resume.

EMA200 is suitable as a slow regime or final invalidation signal. It is unsuitable as the sole runner exit because it reacts late and can surrender a large part of a move. It is also likely to reject useful early reversals if used as a strict entry veto.

The band gap is not volatility by itself. It is the distance between two smoothed price references and varies materially by symbol and price scale. It must be normalized before comparing gold, BTC, EURUSD, and USTEC.

## Band-state measurements to log before filtering

Use completed bars only and calculate on both M5 and M15:

- `widthATR = abs(EMA_low_26 - EMA_VWAP_13) / ATR_14`
- `widthPrice = abs(EMA_low_26 - EMA_VWAP_13) / close`
- `expansion3 = widthATR_now - widthATR_3_bars_ago`
- `relativeWidth = widthATR_now / median(widthATR over the prior 24 bars)`
- slopes of EMA(low, 26), smoothed VWAP, and EMA200 over three completed bars

Classify each signal for analysis, without initially rejecting it:

- expanding: `expansion3 > 0` and relative width above 1;
- mature: width above its rolling median but no longer expanding;
- compressing: `expansion3 < 0`;
- compressed: width in the bottom rolling quartile.

Rolling ranks are preferable to one fixed gap threshold because the four symbols have different prices, volatility, and sessions. Intraday periodicity also means the same raw width has different meaning at different times of day.

The July signal snapshots do not justify a simple minimum-width gate. Median accepted versus rejected gaps were 9.43 versus 8.64 basis points for gold H1, but 4.74 versus 7.60 basis points for BTC H1. Winner/loser gap comparisons also changed sign across filters. The level alone is not stable enough; contraction, expansion, direction, and out-of-sample behavior must be measured.

## Candidate exit study

Keep the original protective M5 band stop fixed. Compare runner exits on an identical entry set:

1. **Control:** exit on the first M15 close beyond the latest confirmed swing level.
2. **Band confirmation:** an M15 structure break changes the runner to a warning state. Exit only after a completed M15 candle closes through both band lines against the trade while M15 width is contracting, or after two consecutive adverse band-side closes.
3. **EMA200 final exit:** ignore the local M15 break and exit after a completed M15 close crosses EMA200 against the trade. This is expected to hold longest and give back most.

The recommended first challenger is band confirmation. It uses the M15 break as information without assuming every broken local swing ends the larger trend. EMA200 should be recorded as a regime and tested as the slow exit, not combined immediately with several extra conditions.

## Candidate entry-frequency study

Do not add band width on top of both swing gates; that would lower the trade count further. Replace the restrictive M15 swing veto with a faster band-state context and keep only one higher-timeframe direction rule.

Compare three frozen entry gates with the same M5 arrow, M5 band stop, and fixed 1R outcome first:

1. current H1 or H4 swing direction plus M15 swing direction;
2. higher-timeframe swing direction plus M15 band direction and slope;
3. higher-timeframe band direction and slope plus M15 band direction and slope, with HH/HL labels logged but not used as vetoes.

EMA200 should initially be a report column rather than an entry veto. The screenshots contain early reversals and trends that begin on the other side of EMA200, so a strict price-versus-EMA200 rule would probably reduce frequency and enter late.

## Viability gates

Count unique eligible M5 signals, not the initial runner and 1R leg as two opportunities. Define whether the desired 3-5 trades per day means the four-symbol portfolio or each symbol. In July, the completed H1 tests produced only 33 initial entries across gold, BTC, and EURUSD, about 1.1 per calendar day. The three symbols produced 707 raw closed M5 arrows, about 22.8 per day, so the signal supply exists; the gating is the bottleneck.

For a four-symbol portfolio, accepting roughly 10-20% of raw arrows may reach 3-5 daily opportunities. Requiring 3-5 per symbol would mean 12-20 portfolio opportunities per day and would require much looser gates, higher turnover, and more overlapping risk.

Win rate must be assessed together with realized reward-to-risk and costs:

- 55% wins at 1R gives only +0.10R expectancy before costs;
- 60% wins at 1R gives +0.20R;
- 55% wins at 1.5R gives +0.375R;
- 45% wins at 2R gives +0.35R.

A 55-60% win-rate target is reasonable for the fixed 1R leg, but it should not be imposed on the runner. Trend systems often rely on a minority of large winners. Judge the whole system by net expectancy, profit factor, drawdown, cost per opportunity, 1R/2R/3R reach rates, and runner giveback.

Use at least 200 unique opportunities for initial screening and closer to 400 before treating a 55-60% observed win rate as reasonably precise. Freeze the variants before rerunning July and October. Keep August and September untouched for the later holdout review.

## Research basis and limits

Long-horizon time-series momentum evidence supports the general idea of holding persistent moves, but it studies monthly horizons and does not establish an intraday Simple Trender edge: [Moskowitz, Ooi and Pedersen](https://fairmodel.econ.yale.edu/ec439/mosk.pdf). Trend-following returns are strongly related to the size of market moves, which supports preserving runners when a broad regime remains intact: [AQR, You Can't Always Trend When You Want](https://www.aqr.com/Insights/Research/Journal-Article/You-Cant-Always-Trend-When-You-Want). Research on stock trend trades also finds a highly skewed outcome distribution driven by a small share of winners: [Zarattini, Pagani and Wilcox](https://papers.ssrn.com/sol3/papers.cfm?abstract_id=5084316).

Volatility clustering supports measuring expansion and contraction as persistent states, but it does not validate this custom band width as a trading signal: [Engle, GARCH 101](https://doi.org/10.1257/jep.15.4.157). Testing many threshold combinations on the same months creates selection risk, so use a small predeclared comparison and preserve holdout data: [Bailey et al., Probability of Backtest Overfitting](https://escholarship.org/uc/item/4w1110bb).
