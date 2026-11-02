"""Fast bar-model screen of Simple Trender parameters. Approximate, not MT5 fills."""
from __future__ import annotations

import argparse
import csv
import math
import statistics
from bisect import bisect_right
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path


PROFILES = {
    "base": (26, 13, 3),
    "fast": (23, 11, 2),
    "smooth": (30, 15, 4),
    "ema23": (23, 13, 3),
    "ema30": (30, 13, 3),
    "vwap11": (26, 11, 3),
    "vwap15": (26, 15, 3),
    "slope2": (26, 13, 2),
    "slope4": (26, 13, 4),
}
TFS = (1, 3, 5)
MAJORS = (190, 200, 210)
START = datetime(2026, 10, 12)
END = datetime(2026, 10, 26)


@dataclass(slots=True)
class Bar:
    time: datetime
    available: datetime
    open: float
    high: float
    low: float
    close: float
    volume: int
    spread: int


@dataclass(slots=True)
class Position:
    direction: int
    leg: str
    entry: float
    stop: float
    target: float | None
    risk: float
    opened: datetime
    mfe: float = 0.0


def read_bars(path: Path):
    by_tf = {1: [], 3: [], 5: [], 15: []}
    point = None
    with path.open(newline="", encoding="ascii") as f:
        for row in csv.DictReader(f, delimiter=";"):
            tf = int(row["tf"])
            if tf not in by_tf:
                continue
            t = datetime.strptime(row["time"], "%Y.%m.%d %H:%M")
            if point is None:
                point = 10 ** -len(row["open"].partition(".")[2])
            by_tf[tf].append(
                Bar(t, t + timedelta(minutes=tf), float(row["open"]),
                    float(row["high"]), float(row["low"]), float(row["close"]),
                    int(row["tick_volume"]), int(row["spread_points"]))
            )
    for bars in by_tf.values():
        bars.sort(key=lambda b: b.time)
    return by_tf, point


def quantile(sorted_values, fraction):
    at = (len(sorted_values) - 1) * fraction
    lo, hi = math.floor(at), math.ceil(at)
    return sorted_values[lo] + (sorted_values[hi] - sorted_values[lo]) * (at - lo)


def indicators(bars: list[Bar], band_period: int, vwap_period: int,
               slope: int, major: int):
    n = len(bars)
    ema = [0.0] * n
    smooth = [0.0] * n
    major_ema = [0.0] * n
    atr = [0.0] * n
    width = [0.0] * n
    direction = [0] * n
    arrow = [0] * n
    state = [0] * n
    a = 2 / (band_period + 1)
    b = 2 / (vwap_period + 1)
    c = 2 / (major + 1)
    day = None
    pv = vol = 0.0
    for i, bar in enumerate(bars):
        ema[i] = bar.low if i == 0 else a * bar.low + (1 - a) * ema[i - 1]
        major_ema[i] = bar.close if i == 0 else c * bar.close + (1 - c) * major_ema[i - 1]
        if bar.time.date() != day:
            day = bar.time.date()
            pv = vol = 0.0
        v = max(1, bar.volume)
        pv += ((bar.high + bar.low + bar.close) / 3) * v
        vol += v
        raw_vwap = pv / vol
        smooth[i] = raw_vwap if i == 0 else b * raw_vwap + (1 - b) * smooth[i - 1]
        tr = bar.high - bar.low
        if i:
            tr = max(tr, abs(bar.high - bars[i - 1].close),
                     abs(bar.low - bars[i - 1].close))
        atr[i] = tr if i == 0 else (atr[i - 1] * 13 + tr) / 14
        width[i] = abs(ema[i] - smooth[i]) / atr[i] if atr[i] > 0 else 0.0
        if i:
            previous = bars[i - 1].close
            if bar.close > ema[i] and previous < smooth[i] and bar.close > smooth[i]:
                arrow[i] = 1
            elif bar.close < ema[i] and previous > smooth[i] and bar.close < smooth[i]:
                arrow[i] = -1
        if i >= slope:
            if bar.close > ema[i] and bar.close > smooth[i] and \
               ema[i] > ema[i - slope] and smooth[i] > smooth[i - slope]:
                direction[i] = 1
            elif bar.close < ema[i] and bar.close < smooth[i] and \
                 ema[i] < ema[i - slope] and smooth[i] < smooth[i - slope]:
                direction[i] = -1
        if i >= 27:
            sample = sorted(width[i - 24:i])
            med, q25 = quantile(sample, 0.5), quantile(sample, 0.25)
            rising = width[i] > width[i - 3]
            if width[i] <= q25:
                state[i] = 4  # compressed
            elif rising and width[i] >= med:
                state[i] = 1  # expanding
            elif not rising and width[i] >= med:
                state[i] = 2  # mature
            elif not rising and width[i] > q25:
                state[i] = 3  # contracting
            elif rising and width[i] < med and direction[i] and \
                 direction[i] == direction[i - 3]:
                state[i] = 5  # re-expanding
    return {"ema": ema, "vwap": smooth, "major": major_ema,
            "dir": direction, "arrow": arrow, "state": state}


def quote_exit(position: Position, bid: float, spread_price: float):
    return (bid if position.direction > 0 else bid + spread_price)


def close_position(position: Position, quote: float, time: datetime, reason: str):
    r = position.direction * (quote - position.entry) / position.risk
    return {"leg": position.leg, "direction": position.direction,
            "opened": position.opened, "closed": time, "r": r,
            "reason": reason, "mfe_r": position.mfe / position.risk,
            "giveback_r": (position.mfe - position.direction *
                           (quote - position.entry)) / position.risk}


def bar_hit(position: Position, bar: Bar, spread_price: float, point: float):
    offset = 0 if position.direction > 0 else spread_price
    opened = bar.open + offset
    high, low = bar.high + offset, bar.low + offset
    if position.direction > 0:
        position.mfe = max(position.mfe, high - position.entry)
        if opened <= position.stop:
            return opened, "SL_GAP"
        if position.target is not None and opened >= position.target:
            return opened, "TP_GAP"
        if low <= position.stop:
            return position.stop, "SL"
        if position.target is not None and high >= position.target:
            return position.target, "TP"
    else:
        position.mfe = max(position.mfe, position.entry - low)
        if opened >= position.stop:
            return opened, "SL_GAP"
        if position.target is not None and opened <= position.target:
            return opened, "TP_GAP"
        if high >= position.stop:
            return position.stop, "SL"
        if position.target is not None and low <= position.target:
            return position.target, "TP"
    return None


def simulate(symbol, by_tf, point, profile, signal_tf, major_period, runner):
    band_period, vwap_period, slope = PROFILES[profile]
    signal_bars = by_tf[signal_tf]
    m5_bars = by_tf[5]
    m15_bars = by_tf[15]
    signal = indicators(signal_bars, band_period, vwap_period, slope, major_period)
    m5 = indicators(m5_bars, band_period, vwap_period, slope, major_period)
    m15 = indicators(m15_bars, band_period, vwap_period, slope, major_period) if runner else None
    signal_times = [b.available for b in signal_bars]
    m5_times = [b.available for b in m5_bars]
    m15_times = [b.available for b in m15_bars] if runner else []
    current = {"base": None, "core": None, "sat": None}
    completed = []
    raw = eligible = accepted = blocked = 0
    last_signal = -1
    last_m15 = -1
    for bar in by_tf[1]:
        now = bar.time
        if now < START or now >= END:
            continue
        spread = bar.spread * point
        m5_i = bisect_right(m5_times, now) - 1
        m15_i = bisect_right(m15_times, now) - 1 if runner else -1
        if runner and m15_i > last_m15:
            last_m15 = m15_i
            core = current["core"]
            if core is not None and m15_i >= 1:
                close = m15_bars[m15_i].close
                adverse = (close < min(m15["ema"][m15_i], m15["vwap"][m15_i])
                           if core.direction > 0 else
                           close > max(m15["ema"][m15_i], m15["vwap"][m15_i]))
                crossed = ((m15_bars[m15_i - 1].close >= m15["major"][m15_i - 1]
                            and close < m15["major"][m15_i]) if core.direction > 0
                           else (m15_bars[m15_i - 1].close <= m15["major"][m15_i - 1]
                                 and close > m15["major"][m15_i]))
                if adverse or crossed:
                    for leg in ("core", "sat"):
                        pos = current[leg]
                        if pos is not None:
                            completed.append(close_position(
                                pos, quote_exit(pos, bar.open, spread), now,
                                "M15_EMA" if crossed else "M15_BAND"))
                            current[leg] = None
        # A gap through an existing broker stop/target is resolved at this open.
        for leg, pos in list(current.items()):
            if pos is None:
                continue
            opening = quote_exit(pos, bar.open, spread)
            if (pos.direction > 0 and opening <= pos.stop or
                pos.direction < 0 and opening >= pos.stop):
                completed.append(close_position(pos, opening, now, "SL_GAP"))
                current[leg] = None
            elif pos.target is not None and (
                pos.direction > 0 and opening >= pos.target or
                pos.direction < 0 and opening <= pos.target
            ):
                completed.append(close_position(pos, opening, now, "TP_GAP"))
                current[leg] = None
        if runner and current["core"] is None and current["sat"] is not None:
            pos = current["sat"]
            completed.append(close_position(pos, quote_exit(pos, bar.open, spread), now,
                                            "RUNNER_ENDED"))
            current["sat"] = None
        signal_i = bisect_right(signal_times, now) - 1
        if signal_i > last_signal:
            last_signal = signal_i
            if signal_i >= 1 and signal["arrow"][signal_i]:
                raw += 1
                direction = signal["arrow"][signal_i]
                if m5_i >= 0 and m5["dir"][m5_i] == direction:
                    if not runner or current["core"] is None or m5["state"][m5_i] not in (3, 4):
                        eligible += 1
                        outer = (min(m5["ema"][m5_i], m5["vwap"][m5_i])
                                 if direction > 0 else
                                 max(m5["ema"][m5_i], m5["vwap"][m5_i]))
                        stop = (math.floor(outer / point + 1e-7) - 1) * point if direction > 0 \
                               else (math.ceil(outer / point - 1e-7) + 1) * point
                        entry = bar.open + spread if direction > 0 else bar.open
                        risk = direction * (entry - stop)
                        free = (current["base"] is None if not runner else
                                current["sat"] is None and
                                (current["core"] is None or
                                 current["core"].direction == direction))
                        if risk > point and free:
                            accepted += 1
                            if runner:
                                if current["core"] is None:
                                    current["core"] = Position(direction, "core", entry,
                                                               stop, None, risk, now)
                                current["sat"] = Position(direction, "sat", entry,
                                                          stop, entry + direction * risk,
                                                          risk, now)
                            else:
                                current["base"] = Position(direction, "base", entry,
                                                           stop, entry + direction * risk,
                                                           risk, now)
                        else:
                            blocked += 1
        # Conservative OHLC ordering: if stop and target are both touched, stop wins.
        for leg, pos in list(current.items()):
            if pos is None:
                continue
            hit = bar_hit(pos, bar, spread, point)
            if hit is not None:
                quote, reason = hit
                completed.append(close_position(pos, quote, now, reason))
                current[leg] = None
        if runner and current["core"] is None and current["sat"] is not None:
            pos = current["sat"]
            completed.append(close_position(pos, quote_exit(pos, bar.close, spread), now,
                                            "RUNNER_ENDED"))
            current["sat"] = None
    last = next((b for b in reversed(by_tf[1]) if b.time < END), None)
    if last:
        spread = last.spread * point
        for leg, pos in current.items():
            if pos is not None:
                completed.append(close_position(pos,
                                                quote_exit(pos, last.close, spread),
                                                last.available, "END"))
    fixed = [t for t in completed if t["leg"] != "core"]
    core = [t for t in completed if t["leg"] == "core"]
    positive = sum(t["r"] for t in completed if t["r"] > 0)
    negative = sum(t["r"] for t in completed if t["r"] < 0)
    balance = peak = drawdown = 0.0
    for trade in sorted(completed, key=lambda t: t["closed"]):
        balance += trade["r"] * (0.25 if runner else 0.5)
        peak = max(peak, balance)
        drawdown = max(drawdown, peak - balance)
    return {
        "Symbol": symbol, "SignalTF": f"M{signal_tf}", "Profile": profile,
        "From": START.date().isoformat(), "ToExclusive": END.date().isoformat(),
        "BandEMA": band_period, "VWAPSmooth": vwap_period,
        "SlopeBars": slope, "MajorEMA": major_period,
        "Exit": "runner+1R" if runner else "fixed1R", "StopTF": "M5",
        "RawArrows": raw, "EligibleArrows": eligible,
        "AcceptedEntries": accepted, "BlockedBusyOrStop": blocked,
        "FixedTrades": len(fixed), "FixedWins": sum(t["r"] > 0 for t in fixed),
        "FixedWinRate": round(sum(t["r"] > 0 for t in fixed) / len(fixed), 4) if fixed else 0,
        "FixedExpectancyR": round(statistics.mean(t["r"] for t in fixed), 4) if fixed else 0,
        "RunnerTrades": len(core),
        "RunnerExpectancyR": round(statistics.mean(t["r"] for t in core), 4) if core else 0,
        "AllExpectancyR": round(statistics.mean(t["r"] for t in completed), 4) if completed else 0,
        "ProfitFactorR": round(positive / -negative, 3) if negative else float("inf"),
        "TotalRiskWeightedR": round(sum(t["r"] for t in completed) *
                                    (0.25 if runner else 0.5), 3),
        "MaxDrawdownPctApprox": round(drawdown, 3),
        "RunnerMedianMFER": round(statistics.median(t["mfe_r"] for t in core), 3) if core else 0,
        "RunnerMedianGivebackR": round(statistics.median(t["giveback_r"] for t in core), 3) if core else 0,
    }


def main():
    global START, END
    parser = argparse.ArgumentParser()
    parser.add_argument("bars_dir", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--start", default="2026-10-12")
    parser.add_argument("--end", default="2026-10-26")
    parser.add_argument("--fixed-only", action="store_true")
    parser.add_argument("--profiles", default=",".join(PROFILES))
    parser.add_argument("--timeframes", default=",".join(map(str, TFS)))
    args = parser.parse_args()
    START = datetime.fromisoformat(args.start)
    END = datetime.fromisoformat(args.end)
    if END <= START:
        raise SystemExit("--end must follow --start")
    profiles = [name.strip() for name in args.profiles.split(",")]
    timeframes = [int(value) for value in args.timeframes.split(",")]
    if any(name not in PROFILES for name in profiles) or any(tf not in TFS for tf in timeframes):
        raise SystemExit("Unknown profile or signal timeframe")
    out = args.out or args.bars_dir / "screen_summary.csv"
    rows = []
    for path in (args.bars_dir / f"{symbol}.csv" for symbol in
                 ("XAUUSDm", "BTCUSDm", "EURUSDm", "USTECm")):
        if not path.exists():
            raise SystemExit(f"Missing export: {path}")
        symbol = path.stem
        by_tf, point = read_bars(path)
        for tf in timeframes:
            for profile in profiles:
                rows.append(simulate(symbol, by_tf, point, profile, tf, 200, False))
                if not args.fixed_only:
                    for major in MAJORS:
                        rows.append(simulate(symbol, by_tf, point, profile, tf, major, True))
        print(symbol, "screened", len([r for r in rows if r["Symbol"] == symbol]), "variants")
    if not rows:
        raise SystemExit("No symbol exports found")
    with out.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(out)


if __name__ == "__main__":
    main()
