from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from typing import Any

SCRIPT = Path(__file__).resolve().parents[1] / "evaluate_profile_quality.py"


class ProfileQualityGateTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="profile_quality_gate_")
        self.root = Path(self.temporary.name)
        self.case_files: dict[str, tuple[Path, Path]] = {}
        for stem in ("roll/calibration-01", "roll/holdout-01"):
            real = self.root / "REAL" / f"{stem}.dat"
            target = self.root / "TARGET" / f"{stem}.dat"
            real.parent.mkdir(parents=True, exist_ok=True)
            target.parent.mkdir(parents=True, exist_ok=True)
            real.write_bytes(f"real:{stem}".encode())
            target.write_bytes(f"target:{stem}".encode())
            self.case_files[stem] = (real, target)

        self.manifest_path = self.root / "corpus.json"
        self.candidate_path = self.root / "candidate.json"
        self.baseline_path = self.root / "baseline.json"
        self.report_path = self.root / "report.json"
        self.baseline = self.summary(
            calibration=(4.0, 95.0, -0.5),
            holdout=(5.0, 90.0, -0.4),
        )
        self.candidate = self.summary(
            calibration=(99.0, 1.0, -20.0),
            holdout=(5.2, 89.6, 0.45),
        )
        self.manifest = {
            "schemaVersion": 1,
            "corpusVersion": "synthetic-v1",
            "acceptedBaselineSHA256": self.sha256_bytes(
                self.json_bytes(self.baseline)
            ),
            "cases": [
                self.case("calibration", "roll/calibration-01"),
                self.case("holdout", "roll/holdout-01"),
            ],
            "metrics": [
                {
                    "name": "mean_delta_e2000",
                    "direction": "lowerIsBetter",
                    "allowedRegression": 0.25,
                },
                {
                    "name": "similarity_score_0_100",
                    "direction": "higherIsBetter",
                    "allowedRegression": 0.5,
                },
                {
                    "name": "neutral_a_shift",
                    "direction": "absoluteLowerIsBetter",
                    "allowedRegression": 0.1,
                },
            ],
        }

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def sha256(path: Path) -> str:
        return f"sha256:{hashlib.sha256(path.read_bytes()).hexdigest()}"

    @staticmethod
    def sha256_bytes(value: bytes) -> str:
        return f"sha256:{hashlib.sha256(value).hexdigest()}"

    @staticmethod
    def json_bytes(value: Any) -> bytes:
        return json.dumps(value).encode("utf-8")

    def case(self, role: str, stem: str) -> dict[str, Any]:
        real, target = self.case_files[stem]
        return {
            "role": role,
            "stem": stem,
            "real": {
                "path": real.relative_to(self.root).as_posix(),
                "sha256": self.sha256(real),
            },
            "target": {
                "path": target.relative_to(self.root).as_posix(),
                "sha256": self.sha256(target),
            },
        }

    def summary(
        self,
        calibration: tuple[float, float, float],
        holdout: tuple[float, float, float],
    ) -> dict[str, Any]:
        rows = []
        for stem, values in (
            ("roll/calibration-01", calibration),
            ("roll/holdout-01", holdout),
        ):
            real, target = self.case_files[stem]
            rows.append({
                "stem": stem,
                "real_file": str(real),
                "target_file": str(target),
                "mean_delta_e2000": values[0],
                "similarity_score_0_100": values[1],
                "neutral_a_shift": values[2],
            })
        return {
            "mode": "paired",
            "analyzed": rows,
            "missing_target": [],
            "missing_real": [],
            "duplicate_real_stems": [],
            "duplicate_target_stems": [],
            "failed_pairs": [],
            "config": {},
        }

    def write_inputs(self) -> None:
        self.manifest_path.write_bytes(self.json_bytes(self.manifest))
        self.candidate_path.write_bytes(self.json_bytes(self.candidate))
        self.baseline_path.write_bytes(self.json_bytes(self.baseline))

    def run_gate(
        self, verify_files: str = "all"
    ) -> tuple[subprocess.CompletedProcess[str], dict[str, Any]]:
        self.write_inputs()
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--manifest", str(self.manifest_path),
                "--candidate-summary", str(self.candidate_path),
                "--baseline-summary", str(self.baseline_path),
                "--data-root", str(self.root),
                "--verify-files", verify_files,
                "--report", str(self.report_path),
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        return result, json.loads(result.stdout)

    def test_passes_holdout_with_manifest_declared_allowances(self) -> None:
        result, report = self.run_gate()

        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(report["passed"])
        self.assertEqual(report["status"], "passed")
        self.assertEqual(report["counts"]["comparisons"], 3)
        self.assertEqual(report["counts"]["verifiedFiles"], 4)
        self.assertEqual(
            report["inputHashes"]["acceptedBaselineSummary"],
            self.manifest["acceptedBaselineSHA256"],
        )
        self.assertEqual(report, json.loads(self.report_path.read_text(encoding="utf-8")))

    def test_returns_regression_exit_code_for_holdout_regression(self) -> None:
        self.candidate["analyzed"][1]["mean_delta_e2000"] = 5.26

        result, report = self.run_gate()

        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertFalse(report["passed"])
        self.assertEqual(report["status"], "regression")
        failures = [row for row in report["comparisons"] if not row["passed"]]
        self.assertEqual([row["metric"] for row in failures], ["mean_delta_e2000"])

    def test_rejects_hash_mismatch_as_invalid_input(self) -> None:
        target = self.case_files["roll/holdout-01"][1]
        target.write_bytes(b"changed-after-manifest")

        result, report = self.run_gate()

        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertEqual(report["status"], "invalid")
        self.assertIn("sha256", report["errors"][0])

    def test_rejects_tampered_or_incorrectly_pinned_accepted_baseline(self) -> None:
        original_baseline = deepcopy(self.baseline)
        self.baseline["analyzed"][1]["mean_delta_e2000"] = 100.0

        tampered_result, tampered_report = self.run_gate(verify_files="none")

        self.assertEqual(
            tampered_result.returncode,
            2,
            tampered_result.stdout + tampered_result.stderr,
        )
        self.assertIn("baseline.sha256", tampered_report["errors"][0])

        self.baseline = original_baseline
        self.manifest["acceptedBaselineSHA256"] = "sha256:" + ("0" * 64)
        wrong_pin_result, wrong_pin_report = self.run_gate(verify_files="none")

        self.assertEqual(
            wrong_pin_result.returncode,
            2,
            wrong_pin_result.stdout + wrong_pin_result.stderr,
        )
        self.assertIn("baseline.sha256", wrong_pin_report["errors"][0])

    def test_holdout_hash_mode_skips_calibration_files_only(self) -> None:
        calibration_target = self.case_files["roll/calibration-01"][1]
        calibration_target.write_bytes(b"changed-calibration-output")

        holdout_result, holdout_report = self.run_gate(verify_files="holdout")
        all_result, all_report = self.run_gate(verify_files="all")

        self.assertEqual(
            holdout_result.returncode,
            0,
            holdout_result.stdout + holdout_result.stderr,
        )
        self.assertEqual(holdout_report["counts"]["verifiedFiles"], 2)
        self.assertEqual(all_result.returncode, 2, all_result.stdout + all_result.stderr)
        self.assertEqual(all_report["status"], "invalid")

    def test_rejects_malformed_schema_numbers_and_pairs(self) -> None:
        variants: list[tuple[str, Any]] = []

        future_schema = deepcopy(self.manifest)
        future_schema["schemaVersion"] = 2
        variants.append(("future schema", (future_schema, self.candidate, self.baseline)))

        boolean_allowance = deepcopy(self.manifest)
        boolean_allowance["metrics"][0]["allowedRegression"] = True
        variants.append(("boolean allowance", (boolean_allowance, self.candidate, self.baseline)))

        malformed_baseline_hash = deepcopy(self.manifest)
        malformed_baseline_hash["acceptedBaselineSHA256"] = "not-a-sha256"
        variants.append((
            "malformed baseline hash",
            (malformed_baseline_hash, self.candidate, self.baseline),
        ))

        non_finite = deepcopy(self.candidate)
        non_finite["analyzed"][1]["mean_delta_e2000"] = float("nan")
        variants.append(("NaN metric", (self.manifest, non_finite, self.baseline)))

        infinite = deepcopy(self.candidate)
        infinite["analyzed"][1]["mean_delta_e2000"] = float("inf")
        variants.append(("infinite metric", (self.manifest, infinite, self.baseline)))

        boolean_metric = deepcopy(self.candidate)
        boolean_metric["analyzed"][1]["mean_delta_e2000"] = False
        variants.append(("boolean metric", (self.manifest, boolean_metric, self.baseline)))

        duplicate = deepcopy(self.candidate)
        duplicate["analyzed"].append(deepcopy(duplicate["analyzed"][0]))
        variants.append(("duplicate analyzed pair", (self.manifest, duplicate, self.baseline)))

        missing = deepcopy(self.candidate)
        missing["missing_target"] = ["roll/holdout-01"]
        variants.append(("missing pair", (self.manifest, missing, self.baseline)))

        failed = deepcopy(self.candidate)
        failed["failed_pairs"] = ["roll/holdout-01: decode failed"]
        variants.append(("failed pair", (self.manifest, failed, self.baseline)))

        for name, (manifest, candidate, baseline) in variants:
            with self.subTest(name=name):
                self.manifest = deepcopy(manifest)
                self.candidate = deepcopy(candidate)
                self.baseline = deepcopy(baseline)
                result, report = self.run_gate(verify_files="none")
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(report["status"], "invalid")

    def test_rejects_empty_corpus_calibration_holdout_and_metrics(self) -> None:
        empty_corpus = deepcopy(self.manifest)
        empty_corpus["cases"] = []

        empty_calibration = deepcopy(self.manifest)
        empty_calibration["cases"] = [empty_calibration["cases"][1]]

        empty_holdout = deepcopy(self.manifest)
        empty_holdout["cases"] = [empty_holdout["cases"][0]]

        empty_metrics = deepcopy(self.manifest)
        empty_metrics["metrics"] = []

        for name, manifest in (
            ("empty corpus", empty_corpus),
            ("empty calibration", empty_calibration),
            ("empty holdout", empty_holdout),
            ("empty metrics", empty_metrics),
        ):
            with self.subTest(name=name):
                self.manifest = manifest
                result, report = self.run_gate(verify_files="none")
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(report["status"], "invalid")


if __name__ == "__main__":
    unittest.main()
