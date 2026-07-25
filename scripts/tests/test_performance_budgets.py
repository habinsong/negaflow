from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/performance/enforce-budgets.py"
SPEC = importlib.util.spec_from_file_location("enforce_budgets", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PerformanceBudgetTests(unittest.TestCase):
    def test_checked_in_budget_accepts_current_report_contract_shape(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.write_report(root / "catalog.json", p95=100, rss=200, bytes_per_frame=2200)
            budget = {
                "schemaVersion": 1,
                "policy": "test",
                "applicability": {"architecture": "arm64", "minimumPhysicalMemoryBytes": 1},
                "reports": {
                    "catalog.json": [{
                        "scenario": "json-decode",
                        "frameCount": 50000,
                        "p95MaximumMilliseconds": 101,
                        "maxRSSAfterMaximumBytes": 201,
                        "bytesPerFrameMaximum": 2201,
                    }]
                },
            }
            budget_path = root / "budget.json"
            budget_path.write_text(json.dumps(budget))

            result = MODULE.evaluate(budget_path, root)

            self.assertEqual(result["status"], "pass")
            self.assertEqual(len(result["comparisons"]), 3)

    def test_regression_fails_with_metric_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.write_report(root / "catalog.json", p95=102, rss=200, bytes_per_frame=2200)
            budget_path = root / "budget.json"
            budget_path.write_text(json.dumps({
                "schemaVersion": 1,
                "policy": "test",
                "applicability": {"architecture": "arm64", "minimumPhysicalMemoryBytes": 1},
                "reports": {"catalog.json": [{
                    "scenario": "json-decode",
                    "frameCount": 50000,
                    "p95MaximumMilliseconds": 101,
                }]},
            }))

            result = MODULE.evaluate(budget_path, root)

            self.assertEqual(result["status"], "fail")
            self.assertIn("p95Milliseconds", result["failures"][0])

    def test_missing_case_and_environment_mismatch_are_invalid_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            self.write_report(root / "catalog.json", p95=1, rss=1, bytes_per_frame=1)
            budget_path = root / "budget.json"
            budget_path.write_text(json.dumps({
                "schemaVersion": 1,
                "policy": "test",
                "applicability": {"architecture": "x86_64", "minimumPhysicalMemoryBytes": 1},
                "reports": {"catalog.json": [{
                    "scenario": "missing",
                    "frameCount": 50000,
                    "p95MaximumMilliseconds": 1,
                }]},
            }))

            with self.assertRaises(MODULE.InvalidEvidence):
                MODULE.evaluate(budget_path, root)

    @staticmethod
    def write_report(path: Path, p95: float, rss: int, bytes_per_frame: float) -> None:
        path.write_text(json.dumps({
            "schemaVersion": 1,
            "configuration": "release",
            "environment": {
                "architecture": "arm64",
                "physicalMemoryBytes": 16,
            },
            "cases": [{
                "scenario": "json-decode",
                "frameCount": 50000,
                "durationMilliseconds": {"p95": p95},
                "memory": {"maxRSSAfterBytes": rss},
                "bytesPerFrame": bytes_per_frame,
            }],
        }))


if __name__ == "__main__":
    unittest.main()
