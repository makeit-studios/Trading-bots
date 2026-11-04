"""Summarize the locked four-month, one-account approximation after audit."""

import csv
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path


HERE = Path(__file__).resolve().parent
ARCHIVE = HERE / "local_tester" / "reports" / "trender_quick_r6a_20261104"
OUT = HERE.parents[1] / "outputs"


def read_csv(path: Path, **kwargs):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle, **kwargs))


def fields(detail: str):
    return dict(re.findall(r"(\w+)=([^ ]+)", detail))


def money(amount):
    value = float(amount)
    return f"-${abs(value):,.2f}" if value < 0 else f"${value:,.2f}"


def main():
    selection = json.loads((HERE / "selection.json").read_text(encoding="utf-8"))
    chosen = [month for month in selection["yyyymm"] if month.startswith(("2024", "2025"))]
    summary = read_csv(ARCHIVE / "summary.csv")[0]
    audit = json.loads((ARCHIVE / "tiered_audit.json").read_text(encoding="utf-8"))
    analyzed = read_csv(ARCHIVE / "audited_summary.csv")[0]
    trades = read_csv(ARCHIVE / "trades.csv")
    events = read_csv(next(ARCHIVE.glob("*.events.csv")), delimiter=";")
    snapshots = {fields(e["detail"])["month"]: fields(e["detail"])
                 for e in events if e["kind"] == "MONTH_SNAPSHOT"}
    if chosen != audit["selected_months"] or summary["Model"] != "open prices only":
        raise ValueError("Selection or model mismatch")
    if float(summary["History Quality"].rstrip("%")) < 98:
        raise ValueError("Bar coverage is below the recorded 98% threshold")

    orders = defaultdict(set)
    sets = Counter()
    errors = Counter(e["kind"] for e in events)
    for event in events:
        month = event["time"][:7].replace(".", "")
        if event["kind"] == "ORDER":
            orders[month].add(fields(event["detail"])["signal"])
        elif event["kind"] == "TIER_SET_OPEN":
            sets[month] += 1
    if sum(map(len, orders.values())) != int(analyzed["AcceptedSignals"]):
        raise ValueError("Accepted signal count does not reconcile")
    if set(orders) - set(chosen):
        raise ValueError("Orders outside chosen months")

    rows = []
    for month in chosen:
        cohort = [t for t in trades if t["EntryTime"][:7].replace(".", "") == month]
        fixed1 = [t for t in cohort if t["Leg"] == "2" and t["ExitReason"] in ("TP", "SL")]
        fixed2 = [t for t in cohort if t["Leg"] == "4" and t["ExitReason"] in ("TP", "SL")]
        rows.append({
            "month": month,
            "opening_balance_usd": float(snapshots[month]["balance"]),
            "entries": len(orders[month]),
            "tier_sets": sets[month],
            "1r_tp": sum(t["ExitReason"] == "TP" for t in fixed1),
            "1r_resolved": len(fixed1),
            "2r_tp": sum(t["ExitReason"] == "TP" for t in fixed2),
            "2r_resolved": len(fixed2),
            "entry_cohort_net_usd": round(sum(float(t["NetUSD"]) for t in cohort), 2),
            "runner_net_usd": round(sum(float(t["NetUSD"]) for t in cohort if t["Leg"] == "1"), 2),
        })
    if round(sum(row["entry_cohort_net_usd"] for row in rows), 2) != round(float(summary["Total Net Profit"]), 2):
        raise ValueError("Cohort net does not reconcile to MT5")

    with (OUT / "SimpleTrender_Random_Months_2024_2025.csv").open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    leg_nets = {leg: sum(float(t["NetUSD"]) for t in trades if t["Leg"] == str(leg)) for leg in (1, 2, 4)}
    target1 = [t for t in trades if t["Leg"] == "2" and t["ExitReason"] in ("TP", "SL")]
    target2 = [t for t in trades if t["Leg"] == "4" and t["ExitReason"] in ("TP", "SL")]
    quality = summary["History Quality"]
    lines = [
        "# Simple Trender: randomly selected 2024–2025 months",
        "",
        "This is one continuous $1,000 USTECm account tested from January 1, 2024 through December 31, 2025. "
        "New entries were permitted only in the four randomly drawn months below. Existing positions retained their usual stops, targets and runner exits during intervening months.",
        "",
        f"The six-year month draw was locked at {selection['drawn_at_utc']} using {selection['method']}.",
        "",
        "The original six-year draw also selected February/April 2020, July/August 2021, May/July 2022, "
        "and August/September 2023. Those eight months were not tested because this Exness profile lacked usable minute history before January 2024. "
        "The 2024–2025 result is an approximation, as the profile supplied no real USTECm ticks before January 2026. "
        "MT5 model 2 uses open prices only. MT5 reported 98% history quality, so bar-history quality was imperfect; the score does not indicate real ticks.",
        "",
        "## Combined account result",
        "",
        "| Entries | Net | Final balance | Profit factor | Maximum relative equity drawdown | 1R TP / TP+SL | 2R TP / TP+SL |",
        "|---:|---:|---:|---:|---:|---:|---:|",
        f"| {analyzed['AcceptedSignals']} | {money(summary['Total Net Profit'])} | {money(1000 + float(summary['Total Net Profit']))} | "
        f"{summary['Profit Factor']} | {summary['Equity Drawdown Relative']} | "
        f"{sum(t['ExitReason']=='TP' for t in target1)}/{len(target1)} | {sum(t['ExitReason']=='TP' for t in target2)}/{len(target2)} |",
        "",
        f"Leg net: runner {money(leg_nets[1])}; 1R fixed {money(leg_nets[2])}; 2R fixed {money(leg_nets[4])}. "
        f"MT5 processed {summary['Bars']} bars and {summary['Ticks']} generated ticks; reported history quality was {quality}. "
        f"There were {audit['rollbacks']} rollback starts and {errors['ERROR']} logged close errors.",
        "",
        "## Drawn months",
        "",
        "Net is attributed to the month in which a position opened; it includes the full result of any position that closed in a later month.",
        "",
        "| Entry month | Opening balance | Unique entries | Three-leg sets | 1R TP / TP+SL | 2R TP / TP+SL | Runner net | All-leg net |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        label = f"{row['month'][:4]}-{row['month'][4:]}"
        lines.append(f"| {label} | {money(row['opening_balance_usd'])} | {row['entries']} | {row['tier_sets']} | {row['1r_tp']}/{row['1r_resolved']} | "
                     f"{row['2r_tp']}/{row['2r_resolved']} | {money(row['runner_net_usd'])} | {money(row['entry_cohort_net_usd'])} |")
    lines += [
        "",
        "## Method and limits",
        "",
        "The existing M15 three-leg research rules used EMA(low)30, smoothed VWAP17, completed M5 direction/slope3, "
        "a frozen M5 band stop, independent 1R and 2R fixed legs, and the M15 band/EMA210 runner exit. "
        "Nominal risk was 3% of current equity with the EA's 90% sizing reserve, targeting at most 2.7% combined entry-to-stop risk before execution effects. "
        "The tester used 1:2000 leverage. The original 2026 year-to-date real-tick test is a different time sample and should not be combined as one account.",
        "",
        "The only EA rule change was an entry-month filter. The month draw was saved before any test results were inspected. "
        "The research source, tester script, inputs, MT5 report, event ledger, reconciled trades and tier-safety audit were archived. "
        "The compiled EA's SHA-256 is recorded in the run manifest. "
        "Open-prices-only fills and missing earlier years prevent this result from establishing a live-trading edge.",
        "",
        f"Research source SHA-256: `{hashlib.sha256((HERE / 'Experts/TrenderRunnerResearchEA.mq5').read_bytes()).hexdigest().upper()}`.",
    ]
    (OUT / "SimpleTrender_Random_Months_2024_2025.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"summary": {"entries": analyzed["AcceptedSignals"], "net": summary["Total Net Profit"], "dd": summary["Equity Drawdown Relative"]}, "months": rows}, indent=2))


if __name__ == "__main__":
    main()
