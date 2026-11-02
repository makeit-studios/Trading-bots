from __future__ import annotations

import argparse
import json
import logging
from datetime import datetime
from decimal import Decimal
from pathlib import Path

from .records import DecisionTape, validate_market_csv


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local MT5 AI decision replay; never connects to a live account")
    parser.add_argument("--csv-dir", type=Path, required=True, help="Directory containing SYMBOL.csv")
    parser.add_argument("--decisions", type=Path, required=True, help="Frozen JSONL decision tape")
    parser.add_argument("--symbol", required=True)
    parser.add_argument("--timeframe", choices=("H1",), default="H1", help="Initial tester supports hourly bars")
    parser.add_argument("--initial-capital", type=Decimal, default=Decimal("10000"))
    parser.add_argument("--max-spread", type=Decimal, default=Decimal("0.0003"), help="Maximum bid/ask spread in price units")
    parser.add_argument("--output-dir", type=Path, default=Path("outputs"))
    parser.add_argument("--validate-only", action="store_true")
    return parser


def run(args: argparse.Namespace) -> None:
    if not args.initial_capital.is_finite() or not args.max_spread.is_finite() or args.initial_capital <= 0 or args.max_spread < 0:
        raise ValueError("Initial capital must be positive and max spread cannot be negative")
    market = validate_market_csv(args.csv_dir / f"{args.symbol}.csv", args.symbol)
    tape = DecisionTape(args.decisions)
    tape.validate_scope(args.symbol, args.timeframe, market.first_bar, market.last_bar)
    manifest = {
        "symbol": args.symbol,
        "timeframe": args.timeframe,
        "market_rows": market.rows,
        "first_bar_utc": market.first_bar,
        "last_bar_utc": market.last_bar,
        "market_sha256": market.sha256,
        "decision_count": len(tape),
        "decision_sha256": tape.sha256,
        "initial_capital": str(args.initial_capital),
        "max_spread": str(args.max_spread),
        "engine": "PyEventBT 0.0.14",
    }
    print(json.dumps(manifest, indent=2))
    if args.validate_only:
        return

    from pyeventbt import (
        BarEvent, MinSizingConfig, Modules, PassthroughRiskConfig,
        SignalEvent, Strategy, StrategyTimeframes,
    )
    from pyeventbt.events.events import OrderType, SignalType
    from pyeventbt.strategy.core.account_currencies import AccountCurrencies

    # PyEventBT 0.0.14 casts strategy IDs to int while creating its simulator.
    strategy_id = "910001"
    strategy = Strategy(logging_level=logging.INFO)
    signal_timeframe = StrategyTimeframes.ONE_HOUR
    emitted: set[str] = set()
    accepted: set[str] = set()
    rejected: list[dict[str, str]] = []

    @strategy.custom_signal_engine(strategy_id=strategy_id, strategy_timeframes=[signal_timeframe])
    def replay(event: BarEvent, modules: Modules):
        if event.timeframe != signal_timeframe or event.symbol != args.symbol:
            return []
        decision = tape.get(event.symbol, args.timeframe, event.datetime)
        if decision is None or decision.action == "HOLD":
            return []
        if decision.bar_time in emitted:
            return []
        emitted.add(decision.bar_time)
        positions = modules.PORTFOLIO.get_number_of_strategy_open_positions_by_symbol(event.symbol)
        if positions["TOTAL"] > 0:
            rejected.append({"bar_time": decision.bar_time, "reason": "open_position"})
            return []
        tick = modules.DATA_PROVIDER.get_latest_tick(event.symbol)
        if not tick or tick.get("bid") is None or tick.get("ask") is None:
            rejected.append({"bar_time": decision.bar_time, "reason": "missing_quote"})
            return []
        bid, ask = Decimal(str(tick["bid"])), Decimal(str(tick["ask"]))
        entry = ask if decision.action == "BUY" else bid
        if ask <= bid or ask - bid > args.max_spread:
            rejected.append({"bar_time": decision.bar_time, "reason": "spread"})
            return []
        if decision.action == "BUY":
            valid_stops = decision.stop_loss < entry < decision.take_profit
            side = SignalType.BUY
        else:
            valid_stops = decision.take_profit < entry < decision.stop_loss
            side = SignalType.SELL
        if not valid_stops:
            rejected.append({"bar_time": decision.bar_time, "reason": "invalid_stops"})
            return []
        accepted.add(decision.bar_time)
        return [SignalEvent(
            symbol=event.symbol,
            time_generated=event.datetime + signal_timeframe.to_timedelta(),
            strategy_id=strategy_id,
            signal_type=side,
            order_type=OrderType.MARKET,
            order_price=entry,
            sl=decision.stop_loss,
            tp=decision.take_profit,
        )]

    strategy.configure_predefined_sizing_engine(MinSizingConfig())
    strategy.configure_predefined_risk_engine(PassthroughRiskConfig())
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    result = strategy.backtest(
        strategy_id=strategy_id,
        initial_capital=float(args.initial_capital),
        symbols_to_trade=[args.symbol],
        csv_dir=str(args.csv_dir.resolve()),
        backtest_name="local_decision_replay",
        start_date=datetime.fromisoformat(market.first_bar).replace(tzinfo=None),
        end_date=datetime.fromisoformat(market.last_bar).replace(tzinfo=None),
        export_backtest_csv=True,
        export_backtest_parquet=False,
        account_currency=AccountCurrencies.USD,
        backtest_results_dir=str(args.output_dir.resolve()),
    )
    unseen = tape.trade_decision_times() - emitted
    if unseen:
        raise ValueError(f"Trade decisions not visited by the backtest: {sorted(unseen)}")
    final_balance = float(result.pnl["BALANCE"].iloc[-1])
    summary = {
        "trade_decisions": len(tape.trade_decision_times()),
        "accepted_signals": len(accepted),
        "rejected_signals": len(rejected),
        "fill_rows": len(result.trades),
        "closed_positions": int((result.trades["DEAL"] == "OUT").sum()) if not result.trades.empty else 0,
        "final_balance": final_balance,
        "net_pnl": final_balance - float(args.initial_capital),
    }
    (args.output_dir / "rejections.json").write_text(json.dumps(rejected, indent=2) + "\n", encoding="utf-8")
    (args.output_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))


def main() -> None:
    args = build_parser().parse_args()
    try:
        run(args)
    except (ValueError, ImportError) as exc:
        raise SystemExit(str(exc)) from exc


if __name__ == "__main__":
    main()

