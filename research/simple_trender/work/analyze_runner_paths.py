"""Read completed real-tick ledgers; produce descriptive trade maps only."""
import csv
import json
import re
import statistics as stats
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "work" / "rsi_quick" / "local_tester" / "reports"
OUT = ROOT / "outputs"
RUNS = [
    ("July", "trender_quick_u_jul_r3_real3", "2026.07.01", "2026.08.01"),
    ("August", "trender_quick_u_aug_r3_real", "2026.08.01", "2026.09.01"),
    ("September", "trender_quick_u_sep_r3_real", "2026.09.01", "2026.10.01"),
    ("October 1-25", "trender_quick_u_oct_r3_real", "2026.10.01", "2026.10.26"),
]

def read_csv(path, **kw):
    with path.open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f, **kw))

def median(values):
    return round(stats.median(values), 3) if values else None

def main():
    selected = {"runners_5plus": [], "runners_1_to_5": [], "fixed_m15_exits": []}
    summaries = []
    for month, folder, start, end in RUNS:
        d = BASE / folder
        run = read_csv(d / "summary.csv")[0]
        rows = read_csv(d / "trades.csv")
        if (run["History Quality"], run["From"], run["To"], run["Model"]) != ("100% real ticks", start, end, "real ticks"):
            raise ValueError(f"Wrong quality or period: {folder}")
        if int(run["Bars"]) <= 0 or int(run["Ticks"]) <= 0:
            raise ValueError(f"No bars or ticks: {folder}")
        if len(rows) != int(run["Total Trades"]) or abs(sum(float(x["NetUSD"]) for x in rows) - float(run["Total Net Profit"])) > .02:
            raise ValueError(f"Count or net does not reconcile: {folder}")
        if any(not (start <= x["EntryTime"][:10] < end and start <= x["ExitTime"][:10] < end) for x in rows):
            raise ValueError(f"Trade outside requested dates: {folder}")
        events = read_csv(next(d.glob("*.events.csv")), delimiter=";")
        if events[0]["kind"] != "START" or events[-1]["kind"] != "END":
            raise ValueError(f"Incomplete events: {folder}")
        errors = Counter(x["detail"] for x in events if x["kind"] == "ERROR")
        exits = {}
        for event in events:
            if event["kind"] == "EXIT":
                fields = dict(re.findall(r"(\w+)=([^\s]+)", event["detail"]))
                exits[fields["id"]] = fields
        for trade in rows:
            if trade["EndOfTest"] == "1":
                continue
            recorded = exits.get(trade["PositionId"])
            if recorded is None or abs(float(recorded["mfeR"]) - float(trade["MFER"])) > 0.0001:
                raise ValueError(f"Trade MFE does not match the event ledger: {folder} {trade['PositionId']}")
        for x in rows:
            x["Month"] = month
            x["Direction"] = "long" if float(x["Entry"]) > float(x["Stop"]) else "short"
            x["PeakTime"] = "not recorded"
        measured = [x for x in rows if x["Leg"] == "1" and x["EndOfTest"] == "0"]
        big = [x for x in measured if float(x["MFER"]) >= 5]
        mid = [x for x in measured if 1 <= float(x["MFER"]) < 5]
        early = [x for x in rows if x["Leg"] == "2" and x["EndOfTest"] == "0" and x["ExitReason"].startswith("M15_")]
        fixed = [x for x in rows if x["Leg"] == "2" and x["EndOfTest"] == "0"]
        for key, group in (("runners_5plus", big), ("runners_1_to_5", mid), ("fixed_m15_exits", early)):
            selected[key].extend(group)
        summaries.append({
            "month": month, "runners_measured": len(measured),
            "runner_end_of_test_unmeasured": sum(x["Leg"] == "1" and x["EndOfTest"] == "1" for x in rows),
            "big": len(big), "big_net": round(sum(float(x["NetUSD"]) for x in big), 2),
            "big_median_mfe": median([float(x["MFER"]) for x in big]),
            "big_median_giveback": median([float(x["GivebackR"]) for x in big]),
            "big_median_net_r": median([float(x["NetR"]) for x in big]),
            "big_median_hold_min": median([float(x["HoldMin"]) for x in big]),
            "big_losers": sum(float(x["NetUSD"]) < 0 for x in big),
            "big_realized_at_least_5r": sum(float(x["NetR"]) >= 5 for x in big),
            "big_exit_reasons": dict(Counter(x["ExitReason"] for x in big)),
            "mid": len(mid), "mid_net": round(sum(float(x["NetUSD"]) for x in mid), 2),
            "mid_losers": sum(float(x["NetUSD"]) < 0 for x in mid),
            "mid_stop_exits": sum(x["ExitReason"] == "SL" for x in mid),
            "mid_median_hold_min": median([float(x["HoldMin"]) for x in mid]),
            "early_fixed": len(early), "early_net": round(sum(float(x["NetUSD"]) for x in early), 2),
            "early_positive": sum(float(x["NetUSD"]) > 0 for x in early),
            "early_median_hold_min": median([float(x["HoldMin"]) for x in early]),
            "early_exit_reasons": dict(Counter(x["ExitReason"] for x in early)),
            "fixed_tp": sum(x["ExitReason"] == "TP" for x in fixed),
            "fixed_sl": sum(x["ExitReason"] == "SL" for x in fixed),
            "fixed_closed": len(fixed),
            "fixed_net_all": round(sum(float(x["NetUSD"]) for x in rows if x["Leg"] == "2"), 2),
            "all_net": float(run["Total Net Profit"]), "equity_dd": run["Equity Drawdown Relative"],
            "error_count": sum(errors.values()), "error_details": dict(errors),
        })
    assert [len(selected[k]) for k in selected] == [45, 132, 153], "Unexpected cohort counts"
    OUT.mkdir(exist_ok=True)
    fields = ["Month","PositionId","Leg","Direction","EntryTime","ExitTime","HoldMin","Entry","Stop","Target",
              "EntryVolume","RiskUSD","MFER","PeakTime","GivebackR","NetR","NetUSD","ExitReason","Report"]
    for name, rows in selected.items():
        with (OUT / f"SimpleTrender_{name}_map.csv").open("w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)
    with (OUT / "SimpleTrender_Ledger_Analysis_Summary.json").open("w", encoding="utf-8") as f:
        json.dump(summaries, f, indent=2)
    print(json.dumps(summaries, indent=2))

if __name__ == "__main__":
    main()
