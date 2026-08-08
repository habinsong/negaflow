import importlib.util
import json
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "software_defect_quality",
    ROOT / "scripts/defect-corpus/evaluate-quality.py",
)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(MODULE)


class SoftwareDefectQualityTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.config = {
            "schemaVersion": 1,
            "policy": "test",
            "corpus": {"doi": "fixture", "expectedPairCount": 2, "sensitivity": 3.0},
            "baseline": {
                "improvedImageCount": 1,
                "regressedImageCount": 1,
                "meanPSNRDelta": 0.0,
                "medianPSNRDelta": 0.0,
                "worstPSNRDelta": -1.0,
                "weightedImprovedPixelFraction": 0.1,
                "weightedRegressedPixelFraction": 0.1,
                "changedPixelFraction": 0.2,
            },
            "tolerance": {"psnrDB": 0.0, "pixelFraction": 0.0},
        }
        self.report = [self.entry("a", 1.0, 0.2, 0.0), self.entry("b", -1.0, 0.0, 0.2)]

    def entry(self, name, delta, improved, regressed):
        return {
            "imageName": name,
            "width": 10,
            "height": 10,
            "sensitivity": 3.0,
            "changedPixelCount": 20,
            "referenceMetrics": {
                "psnrDelta": delta,
                "improvedPixelFraction": improved,
                "regressedPixelFraction": regressed,
            },
        }

    def write(self, name, value):
        path = self.root / name
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_matching_report_passes(self):
        result = MODULE.evaluate(self.write("config.json", self.config), self.write("report.json", self.report))
        self.assertEqual(result["status"], "pass")

    def test_aggregate_regression_fails(self):
        report = deepcopy(self.report)
        report[0]["referenceMetrics"]["psnrDelta"] = -2.0
        result = MODULE.evaluate(self.write("config.json", self.config), self.write("report.json", report))
        self.assertEqual(result["status"], "fail")
        self.assertTrue(result["failures"])

    def test_absolute_quality_floor_is_enforced(self):
        config = deepcopy(self.config)
        config["qualityFloor"] = {
            "improvedImageCount": 1,
            "regressedImageCount": 1,
            "meanPSNRDelta": 0.0,
            "medianPSNRDelta": 0.0,
            "worstPSNRDelta": -1.0,
            "weightedImprovedPixelFraction": 0.1,
            "weightedRegressedPixelFraction": 0.1,
            "changedPixelFraction": 0.2,
        }
        passing = MODULE.evaluate(
            self.write("floor-config.json", config),
            self.write("floor-report.json", self.report),
        )
        self.assertEqual(passing["status"], "pass")

        config["qualityFloor"]["meanPSNRDelta"] = 0.1
        failing = MODULE.evaluate(
            self.write("strict-floor-config.json", config),
            self.write("strict-floor-report.json", self.report),
        )
        self.assertEqual(failing["status"], "fail")
        self.assertTrue(any("quality floor" in failure for failure in failing["failures"]))

    def test_malformed_quality_floor_is_invalid(self):
        config = deepcopy(self.config)
        config["qualityFloor"] = []
        with self.assertRaises(MODULE.InvalidEvidence):
            MODULE.evaluate(
                self.write("bad-floor-config.json", config),
                self.write("bad-floor-report.json", self.report),
            )

    def test_missing_reference_and_wrong_sensitivity_are_invalid(self):
        missing = deepcopy(self.report)
        missing[0]["referenceMetrics"] = None
        with self.assertRaises(MODULE.InvalidEvidence):
            MODULE.evaluate(self.write("config.json", self.config), self.write("missing.json", missing))
        wrong = deepcopy(self.report)
        wrong[0]["sensitivity"] = 6.0
        with self.assertRaises(MODULE.InvalidEvidence):
            MODULE.evaluate(self.write("config.json", self.config), self.write("wrong.json", wrong))

    def test_duplicate_names_and_nonfinite_metrics_are_invalid(self):
        duplicate = deepcopy(self.report)
        duplicate[1]["imageName"] = "a"
        with self.assertRaises(MODULE.InvalidEvidence):
            MODULE.evaluate(self.write("config.json", self.config), self.write("duplicate.json", duplicate))
        nonfinite = deepcopy(self.report)
        nonfinite[0]["referenceMetrics"]["psnrDelta"] = float("nan")
        with self.assertRaises(MODULE.InvalidEvidence):
            MODULE.evaluate(self.write("config.json", self.config), self.write("nan.json", nonfinite))


if __name__ == "__main__":
    unittest.main()
