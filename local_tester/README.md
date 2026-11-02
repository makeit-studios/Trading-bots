# Local MT5 AI tester

This is the first local test layer for a new strategy. It does **not** connect to an MT5 account, call an AI API, or send live orders. Existing `.mq5` files remain separate.

On this machine the project starts from an existing 570 KB EA folder; the installed Python virtual environment is about 771 MB because PyEventBT pulls in NumPy, SciPy, Polars, Numba, Matplotlib, and related packages. The `.venv` folder is ignored by Git.

The test engine is pinned to [PyEventBT 0.0.14](https://pypi.org/project/pyeventbt/0.0.14/), which requires Python 3.12 or newer. PyEventBT is still marked alpha. Its historical input is CSV bars; fill accuracy must later be compared with your broker's MT5 tester or demo fills.

## Inputs

Place broker history in `data/EURUSD.csv` as **headerless MT5 M1 CSV** rows ordered oldest to newest:

```text
2026.01.05,00:00:00,1.10000,1.10008,1.09992,1.10000,100,100,10
```

The nine fields are `date,time,open,high,low,close,tickvol,volume,spread`. Timestamps are treated as UTC. The initial replay strategy aggregates these minute bars to H1. PyEventBT 0.0.14's installed CSV reader requires this format even though its public data-provider guide currently describes a six-column format. Keep market data, account currency, symbol contract settings, spread, commission, and swap assumptions matched to the broker before using performance results.

Put frozen model responses in `decisions/replay.jsonl`, one JSON object per line:

```json
{"symbol":"EURUSD","timeframe":"H1","bar_time":"2026-01-01T10:00:00Z","action":"BUY","stop_loss":1.08,"take_profit":1.12,"model_id":"gemini-example","rules_version":"v1","reason":"Example only"}
```

`action` is `BUY`, `SELL`, or `HOLD`. Bars absent from the tape mean no proposed action. A non-HOLD decision requires both stop and target prices. Keep the full model request, chart image, response, and prompt version separately when decisions are first generated; this tape is the frozen execution input for repeatable backtests.

## Local run

From this directory, with Python 3.12+ available (on this machine, Python 3.13 is installed):

```powershell
& 'C:\Users\Karikari\AppData\Local\Programs\Python\Python313\python.exe' -m venv .venv
.venv\Scripts\python.exe -m pip install -e .
.venv\Scripts\python.exe -m unittest discover -s tests
.venv\Scripts\python.exe examples\make_synthetic_fixture.py
.venv\Scripts\python.exe -m mt5_ai_tester.cli --csv-dir data --decisions decisions\replay.jsonl --symbol EURUSD --validate-only
.venv\Scripts\python.exe -m mt5_ai_tester.cli --csv-dir data --decisions decisions\replay.jsonl --symbol EURUSD --output-dir outputs
```

The generated fixture is synthetic and only checks that replay plumbing works. Replace it with broker history and your actual rule/model decisions for any meaningful performance evaluation.

The CLI validates inputs, records SHA-256 hashes and test settings in `outputs/manifest.json`, then passes the frozen decisions into PyEventBT. It writes `outputs/summary.json` and `outputs/rejections.json` and asks PyEventBT to put its CSV results in `outputs/`. It blocks entries with missing quotes, excessive spread, existing positions, or invalid stop/target direction. Accepted entries are placed for the next H1 bar. The current PyEventBT integration uses its minimum lot sizing and passthrough risk configuration, so this is a **test-only integration** until we add your position sizing and account risk rules.

## Still needed before evaluating a strategy

1. Your precise setup, exit, position management, and risk rules.
2. Broker-specific historical H1 data and symbol specifications.
3. A decision collection step that sends point-in-time snapshots to Grok or Gemini and freezes every response.
4. Fill-cost calibration, an untouched holdout period, and demo forward testing.

