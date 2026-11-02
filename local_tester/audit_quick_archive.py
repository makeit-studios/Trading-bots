"""Normalize a single-run MT5 quick archive, then reconcile its deal ledger."""
import csv
import sys
from pathlib import Path

from analyze_trender_runner import analyze


def main(archive: Path):
    path = archive / "summary.csv"
    with path.open(newline="", encoding="utf-8-sig") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise RuntimeError(f"No completed run in {archive}")
    for row in rows:
        row.setdefault("Configuration", f"{row['SignalTimeframe']}_{row['Profile']}_"
                  f"e{row['Exit']}_ema{row.get('MajorEma', '200')}")
        row.setdefault("Entry", "3")
        row.setdefault("Trend", "1")
        row.setdefault("Window", f"quick_{row['From']}_{row['To']}")
    fieldnames = list(dict.fromkeys(name for row in rows for name in row))
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    analyze(archive, allow_open_prices=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: audit_quick_archive.py ARCHIVE")
    main(Path(sys.argv[1]))
