"""Inspect event-time coverage independently of MT5's aggregate quality score."""

import csv
from collections import Counter, defaultdict
from pathlib import Path


archive = Path(__file__).resolve().parent / "local_tester/reports/trender_quick_r6a_20261104"
events_file = next(archive.glob("*.events.csv"))
counts = defaultdict(Counter)
days = defaultdict(set)
first = {}
last = {}
orders_outside = []
allowed = {"202403", "202408", "202508", "202511"}
with events_file.open(encoding="utf-8-sig", newline="") as handle:
    for event in csv.DictReader(handle, delimiter=";"):
        month = event["time"][:7].replace(".", "")
        counts[month][event["kind"]] += 1
        if event["kind"] == "M15_STATE":
            days[month].add(event["time"][:10])
            first.setdefault(month, event["time"])
            last[month] = event["time"]
        if event["kind"] == "ORDER" and month not in allowed:
            orders_outside.append(event["time"])
for month in sorted(counts):
    print(month, "days", len(days[month]), "M15 bars", counts[month]["M15_STATE"],
          "orders", counts[month]["ORDER"], "first", first.get(month), "last", last.get(month))
print("orders_outside", orders_outside[:5], "count", len(orders_outside))
