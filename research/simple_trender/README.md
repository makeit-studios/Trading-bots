# Simple Trender research handoff

Start with `../../Notes/SimpleTrender_TRUTH.md`, which identifies the current strategy, verified results, unresolved risks and active annual test. This directory contains isolated research files; it is not the canonical EA and none of it is a live deployment.

## Contents

- `work/tiered/Experts/TrenderRunnerResearchEA.mq5`: tested three-leg research implementation (3% and 4.5% nominal inputs), plus its runner, ledger analyzer, audit and report scripts.
- `work/yearly/`: annual-test variant, differing in its allowed risk input up to 5%, and its audit/report scripts. Both the 3% and 5% annual runs are complete and audited.
- `work/runner_exit/`, `work/m15_independent/`, `work/independent_fixed/`: earlier independent-fixed and stop-management research source and tester/analyzer scripts.
- `work/*/local_tester/reports/`: both audited 2026 annual runs and four complete July–October M15 comparisons, including the source-input `.set`, HTML tester report, original event ledger, reconciled trade ledger and summary. The 3% two-leg baseline is under `runner_exit`; the 4.5% two-leg and both tiered runs are under `tiered`.
- `outputs/`: concise research reports, data and comparisons for the current tiered study, runner management, timeframe tests and prior price-path investigation.
- `work/run_yearly_tiered.ps1`, `work/yearly/supervise.ps1`, and `work/yearly/continue_after_supervisor.ps1`: historical local orchestration; inspect paths and current process state before use.

## Reproduction and data boundaries

The tested symbol was Exness USTECm; the historical 2026 tests used model 4 real ticks, an M1 tester chart for tick processing, M15 signal input, $1,000 starting equity, 1:2000 tester leverage, and settings recorded in each `.set` and manifest. Confirm broker history quality and date coverage before comparing runs. A `.set` file is an input configuration, not proof that a run completed; require report, event ledger and successful audit.

The shell runners were written for Windows and a private portable MT5 terminal at `work/runner_exit/portable_terminal`. **That terminal, saved accounts, profile, `.ini` files, tick cache, `.ex5` binaries and credentials are intentionally not versioned.** The tester scripts create `.ini` files from the local terminal profile and disable live automated trading. Provision a separate terminal with no trading charts, compile the research source, configure a demo broker profile, and adjust local paths before running. The scripts for earlier builds reference the historical `C:\MT5\Slave1` terminal: review and adapt them rather than starting a personal/live terminal.

The detailed reports are development evidence, not a proven edge. The retained event ledgers can be large and contain trade simulation details; no saved account IDs or terminal configuration are included. The project `.gitignore` excludes `Pics/`; the original locally available charts were used only for qualitative research and are not the basis for quantified stop claims.

The yearly report and month summaries are included in `outputs/SimpleTrender_2026_YTD_Study.md`. The automated batch used date-only MT5 tester settings and ended November 2, 2026. Long paths can prevent MT5 from loading configuration files; use a short workspace path and run IDs. Hashes in test manifests reflect the original test files; Git line-ending conversion may alter working-tree byte hashes without changing source logic.
