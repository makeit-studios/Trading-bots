# TRUTH FILE — EAs Project
Single source of truth: what exists, what has been done, what we are doing.
Last updated: **2026-10-30** (Atlantic/Reykjavik). Update this file whenever a test, decision, or reorg happens.

**Current Simple Trender handoff:** Read `Notes/SimpleTrender_TRUTH.md` first. It records the latest M5-only entry direction, M1/M3/M5 arrows, M3/M5 stop work, runner behavior, July/October fast screens, the 2026-10-30 VWAP/slope sweep, audited results, and the exact unfinished comparison. The Simple Trender rules in §12 below are historical and superseded.

---

## 1. Folder map (after 2026-10-21 02:39 reorg)

| Folder | Contents |
|---|---|
| `EAs\Experts\` | All EA sources + compiled .ex5 |
| `EAs\Indicators\` | SignalViz.mq5, BodyRangeZones (+README, sync script) |
| `EAs\Notes\` | `Markets structure.txt` (user's video-study notes), **this file** |
| `EAs\local_tester\`, `EAs\Pics\` | test artifacts / screenshots |

## 2. EA inventory & status

| File | What it is | Status |
|---|---|---|
| **StructureZoneEntryEA.mq5** | New H4/M15/M5 XAUUSD structure, zone, and entry EA | **Compiles cleanly; runtime/backtest validation in progress. Separate from older EAs and BodyRangeZones.** |
| **MQL5_Final_Fixed_System.mq5** | Main system: wick-retest + trend-breakout on XAUUSDm | **Rewritten, backtested, validated — ACTIVE** |
| MQL5_Final_Fixed_System.mq5.bak | Original pre-rewrite backup | Archive |
| **Falcon_Score_Based_Pattern_EA.mq5** | 5-point confluence score EA (market structure + sweep + wick + pattern) | **Logic reviewed 10/21 — NEVER backtested** |
| FalconScoreEA_v2.mq5 | Falcon variant (28 KB, largest) | Not reviewed |
| FalconArcRangeEA_ExpertStyle.mq5 | Falcon variant | Not reviewed |
| Experts_claude_first.mq5 | Unknown variant | Not reviewed |
| LiquidityZoneEA.mq5 | Liquidity-zone strategy | Not reviewed |
| MQL5_Integrated_System.mq5 | Older small system (9 KB) | Not reviewed |
| RSI_Oversold_Overbought_EA.mq5 | RSI mean-reversion | Not reviewed |

(All non-reviewed EAs last compiled 2026-07-09, untouched since.)

## 3. Main system — validated configuration

- **What it does:** two signals on M10 — (A) wick-rejection at a 30-bar S/R level (range ≥1.5×ATR, lower wick ≥60%, touch within 0.1×ATR), (B) trend breakout (20-bar break + body ≥70% + ATR expansion >1.2× avg). Limit entry at signal-bar midpoint; expires unfilled after 5 bars. HTF H4 EMA200 filter. One trade at a time.
- **Best validated params (Best1):** XAUUSDm **M10**, SL **1.5×ATR**, TP **4×ATR**, trail **2.0×ATR**, BE **1.25×ATR**, HTF **ON**, risk **1%** — saved as `MF_best1.set` (tester profiles folder).
- **12-month out-of-sample result (2025.10.20–2026.10.20):** net **+1,739.49 (+17.4%)**, PF **1.24**, **164 trades**, max DD **10.8%**, Sharpe **5.23**, expectancy **+10.61/trade**.
- Optimization window was 2026.04.20–2026.10.20 (6 mo, 144 passes, top pass 129); first half of the 12 months was unseen = honest validation.

## 4. What has been done (timeline)

**2026-10-20**
1. Full code review → in-place rewrite of MQL5_Final_Fixed_System (original backed up): correctness bugs, risk hardening, added HTF filter, session/spread inputs, Friday cleanup, OnTester scoring (`Inp_MinTradesForScore`), min-lot handling.
2. 1-month M15/M10 matrix → statistically unusable (2–25 trades/run); optimization scored all zeros (min-trades gate).
3. 12-month M15/M10 matrix (6 verified runs):

   | Run | Net | PF | Trades |
   |---|---|---|---|
   | M15 baseline | −893.93 | 0.75 | — |
   | M15 HTF-off | −1,244.31 | — | — |
   | M15 tight exits | −619.01 | — | — |
   | **M10 baseline** | **+342.83** | **1.07** | 166 |
   | M10 HTF-off | −441.03 (DD 21%) | — | — |
   | M10 tight exits | +88.18 | — | — |

4. 6-month optimization `OPT6_M10` (144 passes, min 20 trades, 20% DD cap) → Best1 params (dense plateau → low overfit risk).
5. Out-of-sample validation: Best1 +1,739.49 (above), Best2 (TP5) +1,324.05 / PF 1.19.
6. $100 / 1:1000 small-account tests (3 months, 2026.07.20–2026.10.20):
   - 1% risk + min-lot guard → **0 trades** (102 signals rejected: calculated lot < 0.01).
   - Min-lot floor ON (0.01 always) → **−98.29, account blown** (31 trades, WR 25.8%, PF 0.61; effective risk 8–13%/trade).
   - $250 deposit @ 5% (≈0.01 lots ≈ 4–5% effective) → **−21.73 (−8.7%), max DD 45.6%**, survived (bad quarter at inflated sizing).

**2026-10-21**
7. SignalViz.mq5 companion indicator (boxes where main EA signals fire). v1 drew nothing — two real bugs found and fixed: (a) series indexing never forced on price arrays, (b) scan range `rates_total − 20000` collapsed to a single bar on charts with <20k bars. Verified via log: `scanned=20000 boxesDrawn=320`.
8. Clutter reduced: default scan = last 500 bars, HTF-blocked signals hidden by default, toggles `Inp_ShowWick/ShowTrend/ShowFiltered`.
9. Falcon_Score_Based_Pattern_EA logic review (see §6).
10. User reorganized folder into `Experts / Indicators / Notes / local_tester / Pics`.

11. **Falcon first-ever backtests** — three 12-month XAUUSDm M15 runs ($10k, 1:100, Model 0, 2025.10.20–2026.10.20), one variable at a time:

    | Version | Net | PF | Trades | WR | Exp/trade | Max DD |
    |---|---|---|---|---|---|---|
    | Baseline (original code) | **−663.12** | 0.55 | 21 | 23.8% | −31.58 | 8.98% |
    | +Phase A (RR≥1 gate, nearest level, 100-bar scan, min-lot policy) | **−577.39** | 0.59 | 20 | 25.0% | −28.87 | 8.14% |
    | +strict trend (A+B) | **−229.29** | 0.60 | 8 | 25.0% | −28.66 | 4.75% |

    All negative. Reports: `R12_M15_Falcon_base/vA/vAB.htm`; logs: `agentlog_R12_Falcon_*.txt` in temp\opencode.
    **Finding:** strict-trend = damage control, not edge — it blocks the 13 sideways trades (59% of all signals) which cuts the loss roughly in half, but per-trade expectancy barely moves (−28.87 → −28.66). The in-trend 5/5 signals themselves still lose ~−29/trade. Only 22 score-5 signals exist per 12 months (0.09% of bars).

12. **Falcon score x timeframe sweep** — XAUUSDm, **$1,000, 1:2000**, Model 0, 12 months (2025.10.20–2026.10.20). Minimized the RR filter (the docs never stated a 1.0 RR requirement, so my Phase A added one that wasn't in the source), so stricter MinScore has room to act:

    | Run | Net | PF | Trades | WR | Exp/trade | Eq DD |
    |---|---|---|---|---|---|---|
    | S3_M10 | −230.86 | 0.95 | 911 | 33.6% | −0.25 | 47.4% |
    | S4_M10 | −104.00 | 0.91 | 235 | 33.2% | −0.44 | 30.7% |
    | S3_M12 | −420.25 | 0.85 | 533 | 31.9% | −0.79 | 54.2% |
    | S4_M12 | −185.84 | 0.72 | 134 | 29.1% | −1.39 | 20.7% |
    | S3_M30 | −84.74 | 0.79 | 67 | 29.9% | −1.26 | 18.1% |
    | S4_M30 | **+38.90** | **1.35** | 20 | 40.0% | +1.95 | 6.2% |

    **The one positive is not real:** S4_M30 skipped **223 signals** for being below min lot (only 20 executed) — ~92% of its signal flow was filtered out by the account-size lot floor, so +38.90 over 20 trades is a tiny, biased sample, not an edge. M12 also distorted (540 skips). Confirms §5 min-lot conclusion on a second EA.
    **Score quality:** PF is flat-to-declining as MinScore rises within M10/M12 (0.95→0.91, 0.85→0.72) → the 5th confirmation adds no edge; more signals = less bleed. Performance difference between timeframes is inside the noise band for the sample sizes.
    Reports: `R12_Falcon_S{3,4}_M{10,12,30}.htm`; logs `agentlog_R12_S*.txt`.

## 5. Locked conclusions (earned — don't re-litigate)

- **HTF filter (H4 EMA200) is protective everywhere** — removing it lost money on every timeframe.
- **Tight exits help M15, hurt M10** — trade management is timeframe-dependent.
- **Win rate ~40% is by design**: TP 4×ATR vs SL 1.5×ATR ⇒ breakeven WR ≈28%, RR ≈2.6:1. Raising WR (e.g. tighter TP) destroys RR — expectancy is the metric, not WR.
- **$100 accounts are incompatible with this instrument on Exness**: 0.01 min lot = 1 oz gold = ~$9–13 per stop = 9–13% risk on $100. Leverage does not help (margin never binds; lot granularity does). Need **≥~$450–900** for 1–2% sizing; validated setup assumed ~$10k @1%.
- **Jul–Oct 2026 was a losing quarter even for validated params** (WR 32.6% vs 40% annual) — every profitable system has losing quarters; risk % scales damage, it does not change edge.
- Midpoint retest entry questioned by user ("buying mid-expansion is wrong") — **untested variable**; proposed entry-mode A/B (midpoint / market-at-close / structural-level retest) is **on hold by user**.

## 6. Falcon review summary (2026-10-21, code read line-by-line)

**Concept:** every new bar, compute a **0–5 confluence score** for BUY and SELL; trade only at `MinScoreToTrade` (default **5 = all five**):
1. Trend alignment — market-structure trend from last 2 swing highs/lows over 120 bars (sideways counts as both directions)
2. Trigger — arc retest (price within $0.15 of a low/high 3–10 bars back) OR momentum candle (body ≥60%, close beyond prior bar)
3. Pattern — flag (correction <40% of an 18-bar impulse) OR wedge (bar range compression <55%)
4. Liquidity sweep — wick beyond prior bar's low, close back above (sell: mirror)
5. Wick rejection — wick ≥35% of range

**Execution:** market order at bar close. SL = swing (10 bars) ±25 pts, clamped to [1.0, 2.5]×ATR. TP = 90% of the path to the most-touched retest level in 250-bar history (≥3 touches), else 90% of 2.0R. Sizing: risk% of equity, margin guard keeps ≥25% free. Scale-in: +1 half-size add when price reaches 35% of the way to TP. Management: hold until TP/SL or a strict "clear reversal" (opposite trend+trigger+sweep+wick all at once); or 1.1×ATR trailing if `HoldUntilClearReversal=false`. OnTester = PF×Sharpe×Recovery×Expectancy×√trades, min 30 trades.

**Findings (before any test):**
- **Dead path at defaults:** in a counter-trend direction the score loses the trend point → max 4 → can never reach `MinScore=5`, so the `strongReversal` escape (line 663/665) is **unreachable** unless the user lowers MinScore ≤4. Default = trend-following only, despite the reversal code.
- **Same min-lot trap as main system:** `NormalizeVolumeToStep` bumps any sub-0.01 lot up to 0.01 — below ~$1,000 equity at 1% risk, **every trade is 0.01 lots and the % setting is ignored** (~$9–13/trade on XAUUSDm).
- Pattern point (flag/wedge) is direction-agnostic → adds +1 to *both* scores; sweep+wick co-occur on the same candle, so "5/5" is closer to ~3–4 independent conditions.
- No HTF/session/spread filter at all; management runs only on new bar; TP/SL are broker-side from open (no BE, no ratchet in default hold mode).
- **Zero backtest data existed for this EA** — now tested (see §4.11): all three versions negative on 12-month M15; regime filter reduces damage but creates no edge.

## 7. How we test (workflow rules — follow exactly)

- **Headless runs:** `terminal64.exe /config:<ini>` with `ShutdownTerminal=1`, `Model=0` (synthesized ticks; **Model=4 real-tick is BLOCKED** — Exness connection drops during bulk tick download, failed twice).
- **Preflight: close MT5 GUI first** (running GUI → ~10s run, exit 0, no report).
- **Do NOT reopen the GUI after runs** (user decision 2026-10-21) — run fully headless; user opens MT5 themselves when needed.
- **Verify every run:** check the .htm report file exists in the terminal data folder before believing success.
- **`.set` files self-mutate** (MT5 rewrites last-used inputs into `MQL5_Final_Fixed_System.set`) — always build variants with `Replace-OrThrow` against current file state.
- **Optimization:** ranges via `.set` (`name=value||start||step||stop||Y|N`), `Optimization=1`, `OptimizationCriterion=6` (OnTester custom).
- **Report parsing:** strip tags → collapse `\s+` → `\s*\|\s*`→`|` → match `Label:\|value`. Optimization reports are Excel-SpreadsheetML.
- Chain scripts live in `C:\Users\Karikari\AppData\Local\Temp\opencode\` (`run_matrix_12mo.ps1`, `run_opt6_m10.ps1`, `run_validate_best.ps1`, `run_100usd.ps1`, `run_minlot.ps1`, `run_5pct.ps1`) — each has preflight guard + report check.
- EA Print snapshots saved as `agentlog_*.txt` there; live agent log: `...\Tester\D0E8209F77C8CF37AD8BF550E51FF075\Agent-127.0.0.1-3000\logs\`.
- MetaEditor exit code 1 is a quirk — trust the log line `Result: 0 errors, 0 warnings`.

## 8. FalconScoreEA_v2 (read + tested 2026-10-21)

**Concept:** same 5-point score as v1 (trend / trigger / pattern / sweep / wick — code near-identical), but v2 **hardcodes the strategy as `#define` constants** and exposes only **5 inputs** (title, magic, risk%, MinScoreToTrade=3, ATR period, trend lookback). Intent per source comment: "NOT tunable - prevents overfitting."

**What v2 adds:** a real risk layer (v1 had none) — 5% daily loss cap, **15% drawdown halt**, 4-consecutive-loss → 4h cooldown, max 3 trades/day, loss-streak size decay (×0.8/loss, floor 0.5), Friday close, news block, 25% free-margin floor, and **state persistence to `Common\Files\FalconScoreEA_v2\*.state`**.

**What v2 removed:** the "90% of retest level" TP machinery (now a plain fixed **3.0×R**); `RetestLookbackFar`/`MinRetestsForLevel` are defined but unused (dead constants). Management now does breakeven + 1.1×ATR trail, but only after price travels a full 1R.

**Findings:**
1. **Identical score bug persists** — `strongReversal` path still unreachable in counter-trend at default MinScore, same as v1.
2. **Same min-lot floor bug** (`NormalizeVolume` still clamps up to min lot).
3. **Score still has no discriminating power:** MinScore 3 and 4 produced **byte-identical** results (−761.99 / 63 trades / 19.05% WR). Matches the v1 finding.
4. **v2 tested worse than v1**, not better: **−761.99 over 3 months** at PF **0.42**, WR 19%, on $5k/1:2000/M10/Model1. And ×8,074 "drawdown limit breached" messages mean the **15% halt truncated the loss** — the true figure is worse.
5. ⚠️ **CRITICAL state-file bug (cost us two runs):** the EA persists risk state to `C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\Common\Files\FalconScoreEA_v2\<SYMBOL>_<PERIOD>.state` — a **shared file across all tester runs and all deposits**. Our first $1k runs loaded `peak=5007.13` (written by the earlier $5k run) against a $1,000 deposit → instant −80% "drawdown" → **363,102 blocked ticks, 0 trades**. The $5k runs were themselves contaminated by `consLoss=1970` + a corrupt cooldown inherited from July/Sept leftovers (size decay pinned to floor). **Every v2 backtest MUST delete this folder before the run.** Backup of the old files: `temp\opencode\falcon_state_backup`.

## 9. Open items

| Item | State |
|---|---|
| Entry-mode A/B for main system (midpoint vs market vs structural retest) | **On hold — user: "come back to this"** |
| Review remaining EAs ("the others") | Falcon done; 5 remaining: FalconScoreEA_v2, FalconArcRange, Experts_claude_first, LiquidityZone, Integrated, RSI |
| Real-tick (Model=4) validation of Best1 | Blocked by Exness connection drops |
| Falcon backtesting | 3 runs done 10/21 (all negative on M15, §4.11); open question: other TFs (H1) or MinScore=4 for statistics — awaiting user direction |
| User's direction | Studying market structure (Notes): trends/BoS/sweeps/supply-demand — possible future criterion for EAs |

## 10. Environment

- Broker **Exness-MT5Trial9**, account **476099737**, symbol **XAUUSDm**, MT5 build **6230**, Windows 11, 7GB RAM.
- Terminal data folder: `C:\Users\Karikari\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\` (reports, `MQL5\Experts\`, `MQL5\Indicators\`, `MQL5\Profiles\Tester\` sets `MF_*`, `MQL5\Logs\`).
- Tester set files: `MF_base / nohtf / tight / opt / opt6 / best1 / best2 / minlot / MF_5pct`.

## 11. New structure-zone EA (separate project)

- `Experts/StructureZoneEntryEA.mq5` and `.ex5` implement the new XAUUSD H4/M15/M5 structure, zone, and entry plan. It does not modify the older EAs or `BodyRangeZones`.
- MetaEditor result on 2026-10-22: **0 errors, 0 warnings**. Source and binary are copied to the terminal Experts folder for testing; the EA has not been attached to a live chart.
- Deterministic replay assertions are available through `InpRunControlledReplay=true`; the final smoke run passed all 21. See `Notes/StructureZoneEntryEA.md` and `local_tester/SZEA_smoke.ini`/`.set`.
- The completed headless XAUUSDm comparison used May-July 2026 for development and August-October 2026 as holdout. The default produced 13/$6.99 development trades/net and 29/$116.85 holdout trades/net, with 8.87% maximum holdout equity drawdown. The loose imbalance-only setting lost $51.52 in development despite making $680.99 in holdout, so no evidence setting is validated as a stable edge. Full numbers, skip reasons, and reports are in `local_tester/reports/20261022_035322/` and `Notes/StructureZoneEntryEA.md`. Broker real-tick validation and exact screenshot price matching remain open.

## 12. Simple Trender research specification (2026-10-27)

- `Notes/SimpleTrender_QuantResearch.md` records the external research, current Simple Trender EA evidence, and a fixed candidate rule set called ST-Q1: H4 direction, M15 context, closed M5 arrow, two-bar stop entry, fixed initial stop/target, execution gates, and risk limits.
- ST-Q1 is **superseded** by `Notes/SimpleTrender_MarketScan_Research.md` after reviewing the multi-market screenshots and the user's H4-market-scan proposal. A new tester-only `Experts/TrenderMarketResearchEA.mq5` compares M15-arrow-only against H4-trend-qualified M15 arrows with matched entry/exit/risk rules. It is not a live EA and does not yet rank or trade a multi-symbol portfolio. The May-October Simple Trender test windows have already informed the design and are diagnostic data; future forward results are needed for an unseen evaluation.
- The earlier environment note that real-tick testing was blocked reflects the 2026-10-21 state. Later `local_tester/reports/la5_bands_20261024_060137/summary.csv` reports 100% real-tick coverage for its completed runs. Check each individual report's quality field.
- The first `TrenderMarketResearchEA` October batch was invalidated by 51 stop-order fills after intended expiry. Corrected July and October runs use broker-side expiry, have zero late fills, and reconcile every closed trade to MT5's net profit. The user narrowed ongoing work to XAUUSDm, BTCUSDm, EURUSDm, and USTECm, and explicitly paused after July before August/September. See `Notes/SimpleTrender_FourMarket_JulOct_Findings.md`; do not run further windows until the rule discussion.
