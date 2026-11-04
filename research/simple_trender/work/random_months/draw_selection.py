"""Draw and lock two distinct calendar months per year before inspecting outcomes."""

import json
import secrets
from datetime import datetime, timezone
from pathlib import Path


destination = Path(__file__).with_name("selection.json")
if destination.exists():
    raise SystemExit(f"Selection already exists: {destination}")

months = {
    str(year): sorted(secrets.SystemRandom().sample(range(1, 13), 2))
    for year in range(2020, 2026)
}
record = {
    "drawn_at_utc": datetime.now(timezone.utc).isoformat(),
    "method": "Python secrets.SystemRandom.sample(range(1, 13), 2), sorted; no redraw",
    "years": "2020-2025 inclusive",
    "months": months,
    "yyyymm": [f"{year}{month:02d}" for year, pair in months.items() for month in pair],
}
destination.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print(json.dumps(record, indent=2))
