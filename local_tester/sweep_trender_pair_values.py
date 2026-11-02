"""Hold each selected symbol's band EMA and entry timeframe; screen VWAP/slope values."""
from __future__ import annotations

import csv
from datetime import datetime
from pathlib import Path

import quick_trender_screen as q


ROOT = Path(__file__).resolve().parent / "reports"
WINDOWS = (
    ("jul", ROOT / "trender_bars_quick_jul_20261029", datetime(2026, 7, 8), datetime(2026, 8, 1)),
    ("oct", ROOT / "trender_bars_quick_oct_20261028", datetime(2026, 10, 12), datetime(2026, 10, 26)),
)
PAIR_SETTINGS = (("BTCUSDm", 3, 23), ("USTECm", 1, 30))
VWAP_PERIODS = (9, 11, 13, 15, 17)
SLOPE_BARS = (2, 3, 4, 5)
MAJOR_EMAS = (190, 200, 210)


def main():
    rows = []
    for window, folder, start, end in WINDOWS:
        q.START, q.END = start, end
        for symbol, signal_tf, band_ema in PAIR_SETTINGS:
            by_tf, point = q.read_bars(folder / f"{symbol}.csv")
            for vwap in VWAP_PERIODS:
                for slope in SLOPE_BARS:
                    profile = f"ema{band_ema}_vwap{vwap}_slope{slope}"
                    q.PROFILES[profile] = (band_ema, vwap, slope)
                    fixed = q.simulate(symbol, by_tf, point, profile, signal_tf, 200, False)
                    fixed["Window"] = window
                    rows.append(fixed)
                    for major in MAJOR_EMAS:
                        runner = q.simulate(symbol, by_tf, point, profile, signal_tf, major, True)
                        runner["Window"] = window
                        rows.append(runner)
            print(window, symbol, "completed", flush=True)
    target = ROOT / "trender_pair_value_sweep_20261030.csv"
    with target.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(target)


if __name__ == "__main__":
    main()
