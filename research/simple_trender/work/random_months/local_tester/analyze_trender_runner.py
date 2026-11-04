"""Audit Trender runner logs, reconcile MT5, and summarize comparable configurations."""

import argparse
import csv
import html
import re
import statistics
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path


def fields(detail: str) -> dict[str, str]:
    return dict(re.findall(r"([A-Za-z][A-Za-z0-9]*)=([^ ]+)", detail))


def amount(value: str) -> float:
    return float(value.replace(" ", ""))


def write_csv(path: Path, rows: list[dict], keys: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=keys)
        writer.writeheader()
        writer.writerows(rows)


def ratio(numerator: float, denominator: float) -> float:
    return round(numerator / denominator, 4) if denominator else 0.0


def end_of_test_deals(report: Path) -> list[dict]:
    source = report.read_text(encoding="utf-16", errors="replace")
    deals = []
    for row in re.findall(r"<tr\b[^>]*>(.*?)</tr>", source, flags=re.I | re.S):
        cells = [html.unescape(re.sub(r"<[^>]+>", "", cell)).strip()
                 for cell in re.findall(r"<td\b[^>]*>(.*?)</td>", row, flags=re.I | re.S)]
        if len(cells) >= 13 and cells[4] == "out" and cells[-1].lower() == "end of test":
            deals.append({"Time": cells[0], "Deal": cells[1], "Side": cells[3],
                          "Volume": amount(cells[5]), "Price": amount(cells[6]),
                          "Swap": amount(cells[8]), "Commission": amount(cells[9]),
                          "Profit": amount(cells[10])})
    return deals


def analyze(archive: Path, allow_open_prices: bool = False) -> None:
    with (archive / "summary.csv").open(newline="", encoding="utf-8-sig") as handle:
        runs = list(csv.DictReader(handle))
    if not runs:
        raise RuntimeError("No completed tester runs")

    metrics, ledger, skip_rows = [], [], []
    run_trades, run_entry_days = {}, {}
    for run in runs:
        tag = run["Report"]
        with (archive / f"{tag}.events.csv").open(newline="", encoding="utf-8-sig", errors="replace") as handle:
            events = list(csv.DictReader(handle, delimiter=";"))
        if not events or events[0]["kind"] != "START" or events[-1]["kind"] != "END":
            raise RuntimeError(f"Incomplete events for {tag}")

        counts = Counter(event["kind"] for event in events)
        for event_kind in ("SKIP", "BLOCKED_ADD"):
            reasons = Counter(event["detail"].split(" signal=", 1)[0]
                              for event in events if event["kind"] == event_kind)
            skip_rows.extend({"Report": tag, "Kind": event_kind, "Reason": reason, "Count": count}
                             for reason, count in sorted(reasons.items()))

        positions, accepted_signals, eligible_signals, accepted_days = {}, set(), set(), set()
        stop_decisions = {}
        for event in events:
            data, kind = fields(event["detail"]), event["kind"]
            if kind == "ELIGIBLE":
                eligible_signals.add(data["signal"])
            if kind == "ORDER":
                accepted_signals.add(data["signal"])
                accepted_days.add(event["time"].split(" ", 1)[0])
                source = stop_decisions.get(data["signal"])
                if (source is None and "StopBand" in run) or (source is not None and
                    abs(float(source["stop"]) - float(data["stop"])) > 1e-6):
                    raise RuntimeError(f"Missing or mismatched frozen stop for {tag}: {data['signal']}")
            if kind == "STOP_BAND":
                stop_decisions[data["signal"]] = data
                seconds = {"M1": 60, "M3": 180, "M5": 300}.get(data["source"])
                signal_seconds = {"M1": 60, "M3": 180, "M5": 300, "M15": 900}.get(
                    run.get("SignalTimeframe", "M5"), 300)
                decision_time = int((datetime.strptime(event["time"], "%Y.%m.%d %H:%M:%S") -
                                     datetime(1970, 1, 1)).total_seconds())
                if seconds is None or signal_seconds is None or \
                   int(data["sourceBar"]) + seconds > decision_time or \
                   int(data["signal"]) + signal_seconds > decision_time:
                    raise RuntimeError(f"Signal or stop band was incomplete at decision time in {tag}: {data}")
            if kind == "FILL":
                ident = data["id"]
                current = positions.setdefault(ident, {
                    "Report": tag, "PositionId": ident, "Leg": int(data["leg"]),
                    "EntryTime": event["time"], "Entry": float(data["entry"]),
                    "Stop": float(data["stop"]), "Target": float(data["target"]),
                    "RiskUSD": 0.0, "EntryVolume": 0.0, "ExitVolume": 0.0, "NetUSD": 0.0,
                    "MFER": 0.0, "GivebackR": 0.0, "HoldMin": 0.0,
                    "ExitTime": "", "ExitReason": "", "EndOfTest": 0,
                })
                current["EntryVolume"] += float(data["volume"])
                current["RiskUSD"] += float(data.get("riskUSD", 0))
                current["NetUSD"] += sum(float(data.get(key, 0)) for key in ("profit", "commission", "swap"))
            if kind == "EXIT":
                ident = data["id"]
                if ident not in positions:
                    raise RuntimeError(f"Exit without entry in {tag}: {ident}")
                current = positions[ident]
                current["ExitTime"], current["Exit"] = event["time"], float(data["exit"])
                current["NetUSD"] += sum(float(data.get(key, 0)) for key in ("profit", "commission", "swap"))
                current["MFER"] = max(current["MFER"], float(data["mfeR"]))
                current["GivebackR"], current["HoldMin"] = float(data["givebackR"]), float(data["holdMin"])
                current["ExitReason"] = data.get("exitRule", data["reason"])
                current["ExitVolume"] += float(data["volume"])

        forced_deals = end_of_test_deals(archive / f"{tag}.htm")
        for deal_index, deal in enumerate(forced_deals):
            remaining = [t for t in positions.values() if not t["ExitTime"] and
                         abs(t["EntryVolume"] - deal["Volume"]) < 1e-6 and
                         ((t["Entry"] < t["Stop"]) == (deal["Side"] == "buy"))]
            # Identical simultaneous legs have indistinguishable end-of-test
            # closes. Their economics are identical, so either pairing yields
            # the same per-leg net; retain the separate leg identities.
            if len(remaining) > 1:
                signatures = {(t["EntryTime"], t["Entry"], t["Stop"], t["EntryVolume"])
                              for t in remaining}
                matching_deals = [d for d in forced_deals[deal_index:] if
                                  all(d[k] == deal[k] for k in
                                      ("Time", "Side", "Volume", "Price", "Swap", "Commission", "Profit"))]
                if len(signatures) == 1 and len(matching_deals) == len(remaining):
                    remaining = remaining[:1]
            if len(remaining) != 1:
                raise RuntimeError(f"Cannot uniquely match MT5 end-of-test deal {deal['Deal']} in {tag}")
            current = remaining[0]
            current["ExitTime"], current["Exit"] = deal["Time"], deal["Price"]
            current["ExitVolume"] += deal["Volume"]
            current["NetUSD"] += deal["Profit"] + deal["Commission"] + deal["Swap"]
            current["HoldMin"] = round((datetime.strptime(deal["Time"], "%Y.%m.%d %H:%M:%S") -
                                        datetime.strptime(current["EntryTime"], "%Y.%m.%d %H:%M:%S")).total_seconds() / 60, 2)
            current["ExitReason"] = "end of test"
            current["EndOfTest"] = 1

        trades = list(positions.values())
        if any(not t["ExitTime"] or t["Stop"] <= 0 or t["RiskUSD"] <= 0 or
               abs(t["EntryVolume"] - t["ExitVolume"]) > 1e-6 for t in trades):
            raise RuntimeError(f"Unclosed, unprotected, or unmeasured position in {tag}")
        for trade in trades:
            trade["NetUSD"] = round(trade["NetUSD"], 2)
            trade["NetR"] = round(trade["NetUSD"] / trade["RiskUSD"], 4)
            trade["Reached1R"] = int(trade["MFER"] >= 1)
            trade["Reached2R"] = int(trade["MFER"] >= 2)
            trade["Reached3R"] = int(trade["MFER"] >= 3)
        report_count, report_net = int(run["Total Trades"].replace(" ", "")), amount(run["Total Net Profit"])
        ledger_net = round(sum(t["NetUSD"] for t in trades), 2)
        if len(trades) != report_count or abs(ledger_net - report_net) > 0.02:
            raise RuntimeError(f"Ledger mismatch {tag}: {len(trades)} / {ledger_net} vs {report_count} / {report_net}")
        if allow_open_prices:
            if run.get("Model") != "open prices only" or \
               float(run["History Quality"].rstrip("%")) < 98 or \
               int(run.get("Bars", 0)) <= 0 or int(run.get("Ticks", 0)) <= 0:
                raise RuntimeError(f"Invalid open-price tester report in {tag}")
        elif run["History Quality"] != "100% real ticks":
            raise RuntimeError(f"History quality below 100% real ticks in {tag}: {run['History Quality']}")

        ledger.extend(trades)
        run_trades[tag] = trades
        run_entry_days[tag] = accepted_days
        runners = [t for t in trades if t["Leg"] == 1]
        fixed = [t for t in trades if t["Leg"] in {2, 3, 4}]
        initial_deposit = float(run.get("Deposit") or 10000)
        if initial_deposit <= 0:
            raise RuntimeError(f"Invalid initial deposit in {tag}: {initial_deposit}")
        metrics.append({
            "Report": tag, "Symbol": run["Symbol"], "Configuration": run.get("Configuration", "legacy"),
            "Entry": run.get("Entry", "0"), "SignalTimeframe": run.get("SignalTimeframe", "M5"),
            "StopBand": run.get("StopBand", "0"),
            "Trend": run["Trend"], "Exit": run["Exit"], "Window": run["Window"],
            "From": run["From"], "To": run["To"], "HistoryQuality": run["History Quality"],
            "M5Signals": counts["SIGNAL"], "EligibleSignals": len(eligible_signals),
            "AcceptedSignals": len(accepted_signals), "ActiveEntryDays": len(accepted_days),
            "FilledLegs": counts["FILL"],
            "CompletedTrades": len(trades), "NetUSD": report_net,
            "NetPctInitial": round(report_net / initial_deposit * 100, 3),
            "ProfitFactor": run["Profit Factor"], "EquityDrawdown": run["Equity Drawdown Relative"],
            "AllExpectancyR": round(statistics.mean([t["NetR"] for t in trades]), 4) if trades else 0,
            "FixedTrades": len(fixed), "FixedWins": sum(t["NetUSD"] > 0 for t in fixed),
            "FixedWinRate": ratio(sum(t["NetUSD"] > 0 for t in fixed), len(fixed)),
            "FixedExpectancyR": round(statistics.mean([t["NetR"] for t in fixed]), 4) if fixed else 0,
            "MedianHoldMin": round(statistics.median([t["HoldMin"] for t in trades]), 2) if trades else 0,
            "ReachMeasuredTrades": sum(not t["EndOfTest"] for t in trades),
            "EndOfTestExits": sum(t["EndOfTest"] for t in trades),
            "Reached1R": sum(t["Reached1R"] for t in trades), "Reached2R": sum(t["Reached2R"] for t in trades),
            "Reached3R": sum(t["Reached3R"] for t in trades), "RunnerCount": len(runners),
            "RunnerMedianMFER": round(statistics.median([t["MFER"] for t in runners]), 3) if runners else 0,
            "RunnerMedianGivebackR": round(statistics.median([t["GivebackR"] for t in runners]), 3) if runners else 0,
            "RunnerMedianHoldMin": round(statistics.median([t["HoldMin"] for t in runners]), 2) if runners else 0,
            "SLExits": sum(t["ExitReason"] == "SL" for t in trades), "TPExits": sum(t["ExitReason"] == "TP" for t in trades),
            "ExpertExits": sum(t["ExitReason"] not in {"SL", "TP"} for t in trades),
            "WarningOns": counts["WARNING_ON"], "WarningClears": counts["WARNING_CLEAR"],
            "BlockedAdds": counts["BLOCKED_ADD"], "Skips": counts["SKIP"], "Errors": counts["ERROR"],
        })

    grouped = defaultdict(list)
    for metric in metrics:
        grouped[(metric["Configuration"], metric["Window"])].append(metric)
    portfolio_rows = []
    for (configuration, window), items in sorted(grouped.items()):
        days = (date.fromisoformat(items[0]["To"].replace(".", "-")) -
                date.fromisoformat(items[0]["From"].replace(".", "-"))).days
        group_trades = [t for item in items for t in run_trades[item["Report"]]]
        fixed = [t for t in group_trades if t["Leg"] in {2, 3, 4}]
        runners = [t for t in group_trades if t["Leg"] == 1]
        active_days = set().union(*(run_entry_days[item["Report"]] for item in items))
        fixed_wins = sum(t["NetUSD"] > 0 for t in fixed)
        portfolio_rows.append({
            "Configuration": configuration, "Window": window, "Symbols": len(items), "CalendarDays": days,
            "RawSignals": sum(i["M5Signals"] for i in items),
            "EligibleSignals": sum(i["EligibleSignals"] for i in items),
            "EligiblePerDay": ratio(sum(i["EligibleSignals"] for i in items), days),
            "AcceptedSignals": sum(i["AcceptedSignals"] for i in items),
            "EntriesPerDay": ratio(sum(i["AcceptedSignals"] for i in items), days),
            "ActiveEntryDays": len(active_days),
            "EntriesPerActiveDay": ratio(sum(i["AcceptedSignals"] for i in items), len(active_days)),
            "FixedTrades": len(fixed), "FixedWins": fixed_wins, "FixedWinRate": ratio(fixed_wins, len(fixed)),
            "FixedExpectancyR": round(statistics.mean([t["NetR"] for t in fixed]), 4) if fixed else 0,
            "AllExpectancyR": round(statistics.mean([t["NetR"] for t in group_trades]), 4) if group_trades else 0,
            "ReachMeasuredTrades": sum(not t["EndOfTest"] for t in group_trades),
            "EndOfTestExits": sum(t["EndOfTest"] for t in group_trades),
            "Reached1RRate": ratio(sum(t["Reached1R"] for t in group_trades), sum(not t["EndOfTest"] for t in group_trades)),
            "Reached2RRate": ratio(sum(t["Reached2R"] for t in group_trades), sum(not t["EndOfTest"] for t in group_trades)),
            "Reached3RRate": ratio(sum(t["Reached3R"] for t in group_trades), sum(not t["EndOfTest"] for t in group_trades)),
            "RunnerCount": len(runners),
            "RunnerMedianMFER": round(statistics.median([t["MFER"] for t in runners]), 3) if runners else 0,
            "RunnerMedianGivebackR": round(statistics.median([t["GivebackR"] for t in runners]), 3) if runners else 0,
            "Note": "Frequency and trade statistics only; standalone account balances are not summed as a portfolio.",
        })

    write_csv(archive / "audited_summary.csv", metrics, list(metrics[0]))
    write_csv(archive / "portfolio_frequency.csv", portfolio_rows, list(portfolio_rows[0]))
    write_csv(archive / "trades.csv", ledger, list(ledger[0]) if ledger else ["Report", "PositionId"])
    write_csv(archive / "skip_reasons.csv", skip_rows, ["Report", "Kind", "Reason", "Count"])
    print(f"Audited {len(metrics)} runs and {len(ledger)} closed trades; all ledgers reconciled")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--allow-open-prices", action="store_true")
    arguments = parser.parse_args()
    analyze(arguments.archive, arguments.allow_open_prices)
