"""Preserve per-run MT5 research events and count each gate's observed outcome."""

import argparse
import csv
import datetime as dt
import html
import re
from collections import Counter
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("tester_log", type=Path)
    args = parser.parse_args()

    with (args.archive / "summary.csv").open(newline="", encoding="utf-8-sig") as f:
        runs = list(csv.DictReader(f))
    raw_log = args.tester_log.read_bytes()
    log_encoding = "utf-16" if raw_log.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    lines = raw_log.decode(log_encoding, errors="replace").splitlines()
    start_re = re.compile(r"TMR START (\S+) NONE score=.*: mode=(\d+)")
    end_re = re.compile(r"TMR END (\S+) NONE score=")
    segments = []
    current = None
    for line in lines:
        start = start_re.search(line)
        if start:
            run_match = re.search(r"\brun=(\S+)", line)
            current = {"symbol": start.group(1), "mode": start.group(2),
                       "runid": run_match.group(1) if run_match else None,
                       "lines": [line]}
            continue
        if current is not None:
            if "TMR " in line:
                current["lines"].append(line)
            if end_re.search(line):
                segments.append(current)
                current = None

    counts = []
    skips = []
    late_orders = []
    trades = []
    next_segment = 0
    for run in runs:
        matching_ids = [index for index in range(next_segment, len(segments))
                        if segments[index]["runid"] and
                        segments[index]["runid"].startswith(run["Report"])]
        if matching_ids:
            index = matching_ids[0]
        else:
            candidates = [index for index in range(next_segment, len(segments))
                          if segments[index]["symbol"] == run["Symbol"] and
                          segments[index]["mode"] == run["Mode"] and
                          not segments[index]["runid"] and
                          run["From"] in segments[index]["lines"][0]]
            index = candidates[0] if candidates else -1
        if index < 0:
            raise RuntimeError(f"No completed event segment for {run['Report']}")
        segment = segments[index]
        next_segment = index + 1

        event_lines = segment["lines"]
        (args.archive / f"{run['Report']}_events.log").write_text(
            "\n".join(event_lines) + "\n", encoding="utf-8"
        )
        events = Counter()
        reasons = Counter()
        for line in event_lines:
            match = re.search(r"TMR (START|END|SCAN|SIGNAL|SKIP|ORDER|CANCEL|ERROR)\b", line)
            if not match:
                continue
            kind = match.group(1)
            events[kind] += 1
            if kind == "SCAN":
                events["SCAN_eligible" if "eligible=1" in line else "SCAN_ineligible"] += 1
            if kind == "SKIP":
                reason = line.split(": ", 1)[-1]
                reason = re.sub(r"[-+]?\d+(?:\.\d+)?", "#", reason)
                reasons[reason] += 1
        counts.append({"Report": run["Report"], **{
            key: events[key] for key in (
                "SCAN", "SCAN_eligible", "SCAN_ineligible", "SIGNAL", "SKIP",
                "ORDER", "CANCEL", "ERROR"
            )
        }})
        skips.extend({"Report": run["Report"], "Reason": reason, "Count": count}
                     for reason, count in sorted(reasons.items()))

        report_bytes = (args.archive / f"{run['Report']}.htm").read_bytes()
        report_encoding = "utf-16" if report_bytes.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
        report_html = report_bytes.decode(report_encoding, errors="replace")
        orders_html, deals_html = report_html.split("<b>Deals</b>", 1)
        order_by_id = {}
        order_states = Counter()
        for row_html in re.findall(r"<tr\b[^>]*>(.*?)</tr>", orders_html,
                                   flags=re.DOTALL | re.IGNORECASE):
            cells = [html.unescape(re.sub(r"<[^>]*>", "", raw).strip())
                     for raw in re.findall(r"<td\b[^>]*>(.*?)</td>", row_html,
                                           flags=re.DOTALL | re.IGNORECASE)]
            if len(cells) < 11 or cells[3] not in ("buy stop", "sell stop"):
                continue
            order_states[cells[-2]] += 1
            if not cells[-1].startswith("TMR:"):
                continue
            order_by_id[cells[1]] = cells
            if cells[-2] != "filled":
                continue
            signal_epoch = int(cells[-1][4:])
            expiry = dt.datetime.fromtimestamp(signal_epoch, dt.timezone.utc) + dt.timedelta(minutes=45)
            fill = dt.datetime.strptime(cells[-3], "%Y.%m.%d %H:%M:%S").replace(tzinfo=dt.timezone.utc)
            if fill > expiry:
                late_orders.append({"Report": run["Report"], "Order": cells[1],
                                    "Signal": dt.datetime.fromtimestamp(signal_epoch, dt.timezone.utc).isoformat(),
                                    "Expiry": expiry.isoformat(), "Fill": fill.isoformat()})

        first_trade = len(trades)
        open_trade = None
        for row_html in re.findall(r"<tr\b[^>]*>(.*?)</tr>", deals_html,
                                   flags=re.DOTALL | re.IGNORECASE):
            cells = [html.unescape(re.sub(r"<[^>]*>", "", raw).strip())
                     for raw in re.findall(r"<td\b[^>]*>(.*?)</td>", row_html,
                                           flags=re.DOTALL | re.IGNORECASE)]
            if len(cells) != 13 or cells[4] not in ("in", "out"):
                continue
            if cells[4] == "in":
                if open_trade is not None:
                    raise RuntimeError(f"Overlapping/partial entry in {run['Report']}")
                order = order_by_id.get(cells[7])
                if order is None:
                    raise RuntimeError(f"Missing entry order {cells[7]} in {run['Report']}")
                signal_epoch = int(order[-1][4:])
                open_trade = {
                    "Report": run["Report"], "Signal": dt.datetime.fromtimestamp(signal_epoch, dt.timezone.utc).isoformat(),
                    "Expiry": (dt.datetime.fromtimestamp(signal_epoch, dt.timezone.utc) + dt.timedelta(minutes=45)).isoformat(),
                    "OrderTime": order[0], "FillTime": cells[0],
                    "Direction": "BUY" if cells[3] == "buy" else "SELL",
                    "Volume": cells[5], "RequestedEntry": order[5], "ActualEntry": cells[6],
                    "InitialStop": order[6], "Target": order[7],
                    "EntryCommission": float(cells[8].replace(" ", "")),
                    "EntrySwap": float(cells[9].replace(" ", "")),
                    "EntryProfit": float(cells[10].replace(" ", "")),
                }
            elif open_trade is not None:
                open_trade["ExitTime"] = cells[0]
                open_trade["ActualExit"] = cells[6]
                open_trade["ExitCause"] = "SL" if cells[-1].startswith("sl ") else "TP" if cells[-1].startswith("tp ") else cells[-1]
                open_trade["NetUSD"] = round(
                    open_trade.pop("EntryCommission") + open_trade.pop("EntrySwap") +
                    open_trade.pop("EntryProfit") +
                    float(cells[8].replace(" ", "")) +
                    float(cells[9].replace(" ", "")) +
                    float(cells[10].replace(" ", "")), 2
                )
                direction = 1 if open_trade["Direction"] == "BUY" else -1
                open_trade["EntrySlippagePrice"] = round(
                    direction * (float(open_trade["ActualEntry"]) - float(open_trade["RequestedEntry"])), 8
                )
                trades.append(open_trade)
                open_trade = None
        if open_trade is not None:
            raise RuntimeError(f"Open trade at report end in {run['Report']}")
        counts[-1].update({"ORDER_filled": order_states["filled"],
                           "ORDER_expired": order_states["expired"],
                           "ORDER_canceled": order_states["canceled"] + order_states["cancelled"]})
        report_trades = trades[first_trade:]
        expected_count = int(run["Total Trades"].replace(" ", ""))
        expected_net = float(run["Total Net Profit"].replace(" ", ""))
        if len(report_trades) != expected_count or abs(
            sum(trade["NetUSD"] for trade in report_trades) - expected_net
        ) > 0.02:
            raise RuntimeError(f"Trade ledger does not reconcile to report {run['Report']}")

    with (args.archive / "event_counts.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(counts[0]))
        writer.writeheader()
        writer.writerows(counts)
    with (args.archive / "skip_reasons.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["Report", "Reason", "Count"])
        writer.writeheader()
        writer.writerows(skips)
    with (args.archive / "late_fills.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["Report", "Order", "Signal", "Expiry", "Fill"])
        writer.writeheader()
        writer.writerows(late_orders)
    with (args.archive / "trades.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=[
            "Report", "Signal", "Expiry", "OrderTime", "FillTime", "ExitTime",
            "Direction", "Volume", "RequestedEntry", "ActualEntry", "InitialStop",
            "Target", "ActualExit", "EntrySlippagePrice", "ExitCause", "NetUSD"
        ])
        writer.writeheader()
        writer.writerows(trades)
    print(f"Analyzed {len(counts)} completed test runs, {len(trades)} closed trades; {len(late_orders)} fills after expiry")


if __name__ == "__main__":
    main()
