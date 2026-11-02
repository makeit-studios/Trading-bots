import json
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path

from mt5_ai_tester.records import DecisionTape, validate_market_csv


class RecordTests(unittest.TestCase):
    def test_market_csv_rejects_bad_ohlc(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "EURUSD.csv"
            rows = [f"2026.01.01,00:{minute:02d}:00,1.1,1.2,1.0,1.1,100,100,10" for minute in range(60)]
            rows[-1] = "2026.01.01,00:59:00,1.1,1.0,0.9,1.2,100,100,10"
            path.write_text("\n".join(rows) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "inconsistent OHLC"):
                validate_market_csv(path, "EURUSD")

    def test_tape_rejects_duplicate_and_replays_utc_key(self):
        row = {"symbol": "EURUSD", "timeframe": "H1", "bar_time": "2026-01-01T00:00:00Z", "action": "BUY", "stop_loss": 1.09, "take_profit": 1.12, "model_id": "fixture", "rules_version": "v1", "reason": "test"}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "decisions.jsonl"
            path.write_text(json.dumps(row) + "\n", encoding="utf-8")
            tape = DecisionTape(path)
            decision = tape.get("EURUSD", "H1", datetime(2026, 1, 1, tzinfo=timezone.utc))
            self.assertEqual(decision.action, "BUY")
            path.write_text((json.dumps(row) + "\n") * 2, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate decision"):
                DecisionTape(path)

    def test_trade_requires_stops(self):
        row = {"symbol": "EURUSD", "timeframe": "H1", "bar_time": "2026-01-01T00:00:00Z", "action": "SELL", "model_id": "fixture", "rules_version": "v1", "reason": "test"}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "decisions.jsonl"
            path.write_text(json.dumps(row) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "require stop_loss"):
                DecisionTape(path)


if __name__ == "__main__":
    unittest.main()

