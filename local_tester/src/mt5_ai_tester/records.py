from __future__ import annotations

import csv
import hashlib
import json
import math
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path


def utc_bar_time(value: str | datetime) -> str:
    """Canonical UTC key; timezone-free source timestamps are treated as UTC."""
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00")) if isinstance(value, str) else value
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).isoformat(timespec="seconds")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


@dataclass(frozen=True)
class MarketFile:
    path: Path
    symbol: str
    first_bar: str
    last_bar: str
    rows: int
    sha256: str


def validate_market_csv(path: Path, symbol: str) -> MarketFile:
    if not path.is_file():
        raise ValueError(f"Missing market data: {path}")
    first = last = previous = None
    count = 0
    with path.open("r", newline="", encoding="utf-8-sig") as source:
        reader = csv.reader(source)
        for line_number, row in enumerate(reader, start=1):
            try:
                if len(row) != 9:
                    raise ValueError("expected 9 headerless MT5 M1 CSV fields")
                timestamp = utc_bar_time(datetime.strptime(f"{row[0]} {row[1]}", "%Y.%m.%d %H:%M:%S"))
                values = dict(zip(("open", "high", "low", "close"), (float(value) for value in row[2:6])))
                tick_volume, volume, spread = (int(value) for value in row[6:9])
            except (TypeError, ValueError) as exc:
                raise ValueError(f"{path}:{line_number}: invalid MT5 minute bar: {exc}") from exc
            if any(not math.isfinite(value) for value in values.values()):
                raise ValueError(f"{path}:{line_number}: non-finite price")
            if min(values[name] for name in ("open", "high", "low", "close")) <= 0:
                raise ValueError(f"{path}:{line_number}: prices must be positive")
            if min(tick_volume, volume, spread) < 0:
                raise ValueError(f"{path}:{line_number}: volumes and spread must be nonnegative")
            if values["high"] < max(values["open"], values["close"], values["low"]) or values["low"] > min(values["open"], values["close"], values["high"]):
                raise ValueError(f"{path}:{line_number}: inconsistent OHLC")
            if previous is not None and timestamp <= previous:
                raise ValueError(f"{path}:{line_number}: timestamps must be strictly increasing")
            first = first or timestamp
            last = previous = timestamp
            count += 1
    if count < 60:
        raise ValueError(f"{path}: at least 60 M1 bars are required for an H1 test")
    return MarketFile(path, symbol, first, last, count, file_sha256(path))


@dataclass(frozen=True)
class Decision:
    symbol: str
    timeframe: str
    bar_time: str
    action: str
    stop_loss: Decimal | None
    take_profit: Decimal | None
    model_id: str
    rules_version: str
    reason: str

    @classmethod
    def from_json(cls, row: dict, source: str) -> "Decision":
        try:
            action = str(row["action"]).upper()
            if action not in {"BUY", "SELL", "HOLD"}:
                raise ValueError("action must be BUY, SELL, or HOLD")
            stop_loss = Decimal(str(row["stop_loss"])) if row.get("stop_loss") is not None else None
            take_profit = Decimal(str(row["take_profit"])) if row.get("take_profit") is not None else None
            if action != "HOLD" and (stop_loss is None or take_profit is None):
                raise ValueError("BUY and SELL require stop_loss and take_profit")
            if any(price is not None and (not price.is_finite() or price <= 0) for price in (stop_loss, take_profit)):
                raise ValueError("stop_loss and take_profit must be finite positive prices")
            fields = {name: str(row[name]).strip() for name in ("symbol", "timeframe", "model_id", "rules_version", "reason")}
            if any(not value for value in fields.values()):
                raise ValueError("decision identity and audit fields cannot be blank")
            return cls(**fields, bar_time=utc_bar_time(row["bar_time"]), action=action, stop_loss=stop_loss, take_profit=take_profit)
        except (KeyError, TypeError, InvalidOperation, ValueError) as exc:
            raise ValueError(f"{source}: invalid decision: {exc}") from exc


class DecisionTape:
    def __init__(self, path: Path):
        if not path.is_file():
            raise ValueError(f"Missing decision tape: {path}")
        self.path = path
        self.sha256 = file_sha256(path)
        self._by_key: dict[tuple[str, str, str], Decision] = {}
        with path.open("r", encoding="utf-8-sig") as source:
            for line_number, line in enumerate(source, start=1):
                if not line.strip():
                    continue
                try:
                    row = json.loads(line)
                    if not isinstance(row, dict):
                        raise ValueError("each line must be a JSON object")
                    decision = Decision.from_json(row, f"{path}:{line_number}")
                except (json.JSONDecodeError, ValueError) as exc:
                    raise ValueError(f"{path}:{line_number}: {exc}") from exc
                key = (decision.symbol, decision.timeframe, decision.bar_time)
                if key in self._by_key:
                    raise ValueError(f"{path}:{line_number}: duplicate decision for {key}")
                self._by_key[key] = decision

    def get(self, symbol: str, timeframe: str, bar_time: datetime) -> Decision | None:
        return self._by_key.get((symbol, timeframe, utc_bar_time(bar_time)))

    def validate_scope(self, symbol: str, timeframe: str, first_bar: str, last_bar: str) -> None:
        for decision in self._by_key.values():
            if decision.symbol != symbol or decision.timeframe != timeframe:
                raise ValueError(f"Decision outside configured symbol/timeframe: {decision}")
            if not first_bar <= decision.bar_time <= last_bar:
                raise ValueError(f"Decision outside market date range: {decision}")

    def __len__(self) -> int:
        return len(self._by_key)

    def trade_decision_times(self) -> set[str]:
        return {decision.bar_time for decision in self._by_key.values() if decision.action != "HOLD"}

