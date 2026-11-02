"""Summarize headless StructureZoneEntryEA MT5 reports and decision events.

Usage: python local_tester/summarize_szea.py REPORT_DIRECTORY RUN_ID AGENT_LOG
"""

import csv
import html
import re
import sys
from collections import Counter
from pathlib import Path


LABELS = {
    "trades": "Total Trades",
    "net_profit": "Total Net Profit",
    "payoff": "Expected Payoff",
    "profit_factor": "Profit Factor",
    "equity_drawdown": "Equity Drawdown Maximal",
    "equity_drawdown_relative": "Equity Drawdown Relative",
}


def report_metrics(path: Path) -> dict[str, str]:
    data = path.read_bytes()
    raw = data.decode("utf-16" if data[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8", errors="replace")
    flat = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", raw)))
    result = {}
    for key, label in LABELS.items():
        match = re.search(re.escape(label) + r":\s*([^:]+?)(?=\s+[A-Z][A-Za-z ()%,$./-]+:|$)", flat)
        result[key] = match.group(1).strip() if match else "?"
    return result


def event_summary(path: Path) -> list[dict]:
    runs = []
    current = None
    with path.open(encoding="utf-16" if path.suffix == ".log" else "utf-8-sig",
                   errors="replace", newline="") as stream:
        rows = ((re.search(r"\b(\d{2}:\d{2}:\d{2})\.", line).group(1),
                 match.group(1), match.group(2)) for line in stream
                if (match := re.search(r"\bSZEA (START|ORDER|CANCEL|EXIT|FILL|STATE) (.*)$", line))) if path.suffix == ".log" else (
                    ("", row[2], row[3]) for row in csv.reader(stream, delimiter=";") if len(row) >= 4)
        for wall_time, kind, detail in rows:
            detail = detail.strip()
            if kind == "START":
                current = {"start_wall": wall_time, "events": Counter(), "skip": Counter(), "skip_keys": set()}
                runs.append(current)
            if current is None:
                continue
            current["events"][kind] += 1
            if kind == "STATE" and " skipped: " in detail:
                key, reason = detail.split(" skipped: ", 1)
                reason = reason.split(" retcode=", 1)[0]
                current["skip"][reason] += 1
                current["skip_keys"].add((key, reason))
    return runs


def main() -> None:
    directory, run_id, agent_log = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    paths = [
        directory / f"SZEA_{tag}_{run_id}.htm"
        for tag in (
            "smoke", "development_baseline", "development_any_two",
            "development_imbalance_only", "holdout_baseline",
            "holdout_any_two", "holdout_imbalance_only",
        )
    ]
    # The tester resets its MQL5 Files sandbox each run, but appends to the
    # daily agent log. Find the seven starts from this run ID, even if a later
    # smoke run has appended more lines to the same daily log.
    runs = event_summary(agent_log)
    run_clock = f"{run_id[-6:-4]}:{run_id[-4:-2]}:{run_id[-2:]}"
    if all(path.exists() for path in paths):
        runs = [run for run in runs if run["start_wall"] >= run_clock][:len(paths)]
    else:
        runs = []
    for index, path in enumerate(paths):
        if not path.exists():
            print(f"{path.stem}: MISSING")
            continue
        data = report_metrics(path)
        line = f"{path.stem}: " + ", ".join(f"{k}={v}" for k, v in data.items())
        if index < len(runs):
            ev = runs[index]
            line += (f"; orders={ev['events']['ORDER']} fills={ev['events']['FILL']}"
                     f" unfilled_limits={max(0, ev['events']['ORDER'] - ev['events']['FILL'])}"
                     f" cancels={ev['events']['CANCEL']} exits={ev['events']['EXIT']}"
                     f" unique_skips={len(ev['skip_keys'])}")
            if ev["skip"]:
                line += "; skip_reasons=" + ",".join(f"{k}:{v}" for k, v in ev["skip"].most_common(8))
        print(line)


if __name__ == "__main__":
    main()
