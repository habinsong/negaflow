from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_verifier():
    path = ROOT / "scripts/performance/verify-reports.py"
    spec = importlib.util.spec_from_file_location("verify_reports", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PerformanceSuiteTests(unittest.TestCase):
    def test_suite_is_explicit_opt_in_and_not_part_of_pr_ci(self) -> None:
        suite = (ROOT / "scripts/run-performance-suite.sh").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/performance.yml").read_text(encoding="utf-8")
        ci = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn('NEGAFLOW_PERF:-0', suite)
        self.assertIn("workflow_dispatch", workflow)
        self.assertNotIn("schedule:", workflow)
        self.assertNotIn("run-performance-suite.sh", ci)

    def test_suite_keeps_benchmarks_in_separate_commands(self) -> None:
        suite = (ROOT / "scripts/run-performance-suite.sh").read_text(encoding="utf-8")
        self.assertIn("run-library-query-performance.sh", suite)
        self.assertIn("run-catalog.sh", suite)
        self.assertIn("run-sqlite-catalog.sh", suite)
        self.assertIn("run-interaction.sh", suite)
        self.assertIn("run-defect-removal.sh", suite)

    def test_storage_decision_is_tied_to_measured_scale(self) -> None:
        decision = (ROOT / "docs/architecture/CATALOG_STORAGE.md").read_text(encoding="utf-8")
        self.assertIn("109,721,335", decision)
        self.assertIn("7,446 ms", decision)
        self.assertIn("3,856 ms", decision)
        self.assertIn("SQLite", decision)
        self.assertIn("dual-write", decision)
        self.assertIn("LibraryCatalogHealth", decision)

    def test_report_verifier_accepts_contract_and_rejects_debug(self) -> None:
        verifier = load_verifier()
        report = {
            "schemaVersion": 1,
            "configuration": "release",
            "timingGateApplied": False,
            "storageKind": "whole-catalog-json-snapshot",
            "cases": [
                {
                    "scenario": scenario,
                    "frameCount": 10,
                    "durationMilliseconds": {"samples": [1.0, 2.0]},
                }
                for scenario in (
                    "json-encode",
                    "json-decode",
                    "atomic-write-new-primary",
                    "primary-file-load",
                )
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "catalog.json"
            path.write_text(json.dumps(report), encoding="utf-8")
            verifier.verify_report(path, "catalog")
            report["configuration"] = "debug"
            path.write_text(json.dumps(report), encoding="utf-8")
            with self.assertRaises(ValueError):
                verifier.verify_report(path, "catalog")


if __name__ == "__main__":
    unittest.main()
