"""Create a tiny deterministic plumbing fixture, never a profitability dataset."""

import json
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
DECISIONS = ROOT / "decisions"
DATA.mkdir(exist_ok=True)
DECISIONS.mkdir(exist_ok=True)

start = datetime(2026, 1, 5, tzinfo=timezone.utc)
price = 1.1000
rows = []
for index in range(96 * 60):
    opened = price
    step = 0.00001 if (index < 40 * 60 and index % 20 == 0) or (index >= 40 * 60 and index % 5 == 0) else 0
    price = round(opened + step, 5)
    timestamp = start + timedelta(minutes=index)
    rows.append([
        timestamp.strftime("%Y.%m.%d"), timestamp.strftime("%H:%M:%S"),
        f"{opened:.5f}", f"{max(opened, price) + 0.00008:.5f}",
        f"{min(opened, price) - 0.00008:.5f}", f"{price:.5f}",
        "100", "100", "10",
    ])

with (DATA / "EURUSD.csv").open("w", newline="", encoding="utf-8") as destination:
    for row in rows:
        destination.write(",".join(row) + "\n")

decision = {
    "symbol": "EURUSD",
    "timeframe": "H1",
    "bar_time": (start + timedelta(hours=30)).isoformat(),
    "action": "BUY",
    "stop_loss": 1.0980,
    "take_profit": 1.1040,
    "model_id": "synthetic-fixture",
    "rules_version": "fixture-v1",
    "reason": "Exercises the replay path only; this is not a trading rule",
}
(DECISIONS / "replay.jsonl").write_text(json.dumps(decision) + "\n", encoding="utf-8")
print(f"Created {len(rows)} synthetic EURUSD M1 bars and one H1 replay decision")

