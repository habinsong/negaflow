from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
VALIDATOR_PATH = REPOSITORY_ROOT / "scripts" / "validate_scanner_profiles.py"
SPEC = importlib.util.spec_from_file_location("validate_scanner_profiles", VALIDATOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot import validator: {VALIDATOR_PATH}")
validator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validator)


def stat(value: float = 1.0) -> dict[str, float]:
    return {
        "count": 1.0,
        "mean": value,
        "median": value,
        "p10": value,
        "p90": value,
        "min": value,
        "max": value,
    }


def candidate() -> dict[str, Any]:
    return {
        "stem": "NORITSU/color nega/test-roll/frame-1",
        "realFile": "LUT_target/REAL/NORITSU/color nega/test-roll/frame-1.jpg",
        "p50": 0.5,
        "contrastP90P10": 0.7,
        "midChroma": 20.0,
    }


def profile_payload(profile_id: str = "noritsu__color-nega__test-film") -> dict[str, Any]:
    row = candidate()
    profile: dict[str, Any] = {
        "schemaVersion": 2,
        "id": profile_id,
        "displayName": "NORITSU color nega test film",
        "scanner": "NORITSU",
        "kind": "color nega",
        "filmKey": "test film",
        "validationStatus": "realOnly",
        "rollCount": 1,
        "imageCount": 1,
        "singleRollLimited": True,
        "sourceProfiles": ["SOURCE/NORITSU/color nega/test-roll/profile.json"],
        "tone": {"p50": stat(0.5)},
        "color": {"mid_chroma": stat(20.0)},
        "neutralAxis": {"neutral_a_median": stat(0.0)},
        "neutralAxisBins": [
            {"lumaCenter": 0.5, "coveragePct": 1.0, "labA": 0.0, "labB": 0.0}
        ],
        "texture": {"texture_sharpness_p95": stat(0.5)},
        "sceneBuckets": [
            {
                "family": "luma",
                "name": "mid",
                "imageCount": 1,
                "tone": {"p50": stat(0.5)},
                "color": {"mid_chroma": stat(20.0)},
                "texture": {"texture_sharpness_p95": stat(0.5)},
                "representativeCandidates": [row],
            }
        ],
        "coverageCandidates": [{"axis": "mid", "candidates": [row]}],
    }
    profile["profileHash"] = canonical_hash(profile)
    return profile


def canonical_hash(profile: dict[str, Any]) -> str:
    unhashed = dict(profile)
    unhashed.pop("profileHash", None)
    encoded = json.dumps(
        unhashed,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return f"sha256:{hashlib.sha256(encoded).hexdigest()}"


def write_profile_set(directory: Path, profile: dict[str, Any]) -> None:
    profile_id = str(profile["id"])
    profile_path = directory / f"{profile_id}.json"
    profile_path.write_text(
        json.dumps(profile, ensure_ascii=False), encoding="utf-8"
    )
    file_hash = f"sha256:{hashlib.sha256(profile_path.read_bytes()).hexdigest()}"
    manifest = {
        "schemaVersion": 2,
        "profileCount": 1,
        "profiles": [{
            "id": profile_id,
            "profileHash": profile["profileHash"],
            "fileSHA256": file_hash,
        }],
    }
    (directory / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")


def write_source_contract(root: Path) -> tuple[Path, Path, Path]:
    source = root / "SOURCE"
    profile_path = source / "NORITSU" / "color nega" / "test-roll" / "profile.json"
    profile_path.parent.mkdir(parents=True)
    profile = {
        "mode": "real_only_roll_profile",
        "roll": "NORITSU/color nega/test-roll",
        "image_count": 2,
        "failed_images": [],
        "profile_metadata": {
            "scanner": "NORITSU",
            "kind": "color nega",
            "film_roll": "test-roll",
            "film_key": "test film",
        },
        "tone": {},
        "coarse_zones": {},
        "fine_zones": {},
        "hue_bins": [],
        "neutral_axis": [],
        "texture": {},
        "scene_buckets": {},
        "coverage_candidates": {},
        "representative_candidates": [],
        "cut_summaries": [],
    }
    profile_path.write_text(json.dumps(profile), encoding="utf-8")
    declared_path = "SOURCE/NORITSU/color nega/test-roll/profile.json"
    film_index = {
        "mode": "real_only_film_index",
        "profile_count": 1,
        "groups": [
            {
                "scanner": "NORITSU",
                "kind": "color nega",
                "film_key": "test film",
                "roll_count": 1,
                "image_count": 2,
                "profiles": [declared_path],
            }
        ],
        "profiles": [
            {
                "scanner": "NORITSU",
                "kind": "color nega",
                "film_roll": "test-roll",
                "film_key": "test film",
                "roll": "NORITSU/color nega/test-roll",
                "profile_path": declared_path,
                "image_count": 2,
                "failed_count": 0,
            }
        ],
    }
    index_path = source / "film_index.json"
    index_path.write_text(json.dumps(film_index), encoding="utf-8")
    return source, index_path, profile_path


class ScannerProfileValidatorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.profiles = self.root / "profiles"
        self.source = self.root / "source"
        self.target = self.root / "target"
        self.profiles.mkdir()
        self.source.mkdir()
        self.target.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_empty_paired_profile_directory_exits_nonzero(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(VALIDATOR_PATH),
                "--mode",
                "paired",
                "--profiles",
                str(self.profiles),
                "--source",
                str(self.source),
                "--target",
                str(self.target),
            ],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertNotEqual(result.returncode, 0)
        report = json.loads(result.stdout)
        self.assertFalse(report["passed"])
        self.assertTrue(report["errors"])
        self.assertEqual(report["gateScope"], "coverage-and-smoke-only")
        self.assertFalse(report["qualifiesPairedValidated"])

    def test_source_contract_uses_index_declarations_instead_of_fixed_counts(self) -> None:
        source, _, _ = write_source_contract(self.root)

        report = validator.source_contract(source)

        self.assertTrue(report["passed"])
        self.assertEqual(report["rollProfiles"], 1)
        self.assertEqual(report["declaredProfiles"], 1)
        self.assertEqual(report["groups"], 1)
        self.assertEqual(report["totalImages"], 2)

    def test_source_contract_rejects_group_image_sum_mismatch(self) -> None:
        source, index_path, _ = write_source_contract(self.root)
        film_index = json.loads(index_path.read_text(encoding="utf-8"))
        film_index["groups"][0]["image_count"] = 3
        index_path.write_text(json.dumps(film_index), encoding="utf-8")

        report = validator.source_contract(source)

        self.assertFalse(report["passed"])
        self.assertTrue(any("image_count" in error for error in report["bad"]))

    def test_source_contract_rejects_profile_not_declared_by_index(self) -> None:
        source, _, profile_path = write_source_contract(self.root)
        unlisted = source / "NORITSU" / "color nega" / "unlisted" / "profile.json"
        unlisted.parent.mkdir(parents=True)
        unlisted.write_text(profile_path.read_text(encoding="utf-8"), encoding="utf-8")

        report = validator.source_contract(source)

        self.assertFalse(report["passed"])
        self.assertTrue(any("unlisted" in error for error in report["bad"]))

    def test_empty_manifest_is_rejected(self) -> None:
        (self.profiles / "manifest.json").write_text(
            json.dumps({"schemaVersion": 2, "profileCount": 0, "profiles": []}),
            encoding="utf-8",
        )

        with self.assertRaisesRegex(validator.ProfileValidationError, "must not be empty"):
            validator.profile_contract(self.profiles)

    def test_valid_profile_contract_passes(self) -> None:
        write_profile_set(self.profiles, profile_payload())

        report = validator.profile_contract(self.profiles)

        self.assertTrue(report["passed"])
        self.assertEqual(report["profileCount"], 1)
        self.assertEqual(report["statusCounts"], {"realOnly": 1})

    def test_missing_required_profile_field_is_rejected(self) -> None:
        profile = profile_payload()
        del profile["sourceProfiles"]
        write_profile_set(self.profiles, profile)

        with self.assertRaisesRegex(validator.ProfileValidationError, "sourceProfiles"):
            validator.profile_contract(self.profiles)

    def test_unsupported_profile_schema_is_rejected(self) -> None:
        profile = profile_payload()
        profile["schemaVersion"] = 3
        profile["profileHash"] = canonical_hash(profile)
        write_profile_set(self.profiles, profile)

        with self.assertRaisesRegex(validator.ProfileValidationError, "schemaVersion"):
            validator.profile_contract(self.profiles)

    def test_unsupported_manifest_schema_is_rejected(self) -> None:
        profile = profile_payload()
        write_profile_set(self.profiles, profile)
        manifest_path = self.profiles / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["schemaVersion"] = 3
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        with self.assertRaisesRegex(validator.ProfileValidationError, "schemaVersion"):
            validator.profile_contract(self.profiles)

    def test_unsupported_validation_status_is_rejected(self) -> None:
        profile = profile_payload()
        profile["validationStatus"] = "trustedByDefault"
        profile["profileHash"] = canonical_hash(profile)
        write_profile_set(self.profiles, profile)

        with self.assertRaisesRegex(validator.ProfileValidationError, "validationStatus"):
            validator.profile_contract(self.profiles)

    def test_manifest_and_file_ids_must_match(self) -> None:
        profile = profile_payload()
        write_profile_set(self.profiles, profile)
        manifest_path = self.profiles / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["profiles"][0]["id"] = "noritsu__color-nega__other-film"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        with self.assertRaisesRegex(validator.ProfileValidationError, "ID mismatch"):
            validator.profile_contract(self.profiles)

    def test_manifest_hash_must_match_profile_hash(self) -> None:
        profile = profile_payload()
        write_profile_set(self.profiles, profile)
        manifest_path = self.profiles / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["profiles"][0]["profileHash"] = f"sha256:{'0' * 64}"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        with self.assertRaisesRegex(validator.ProfileValidationError, "does not match profile"):
            validator.profile_contract(self.profiles)

    def test_manifest_file_hash_must_match_profile_bytes(self) -> None:
        profile = profile_payload()
        write_profile_set(self.profiles, profile)
        manifest_path = self.profiles / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["profiles"][0]["fileSHA256"] = f"sha256:{'0' * 64}"
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        with self.assertRaisesRegex(validator.ProfileValidationError, "file hash"):
            validator.profile_contract(self.profiles)

    def test_profile_hash_must_match_canonical_content(self) -> None:
        profile = profile_payload()
        write_profile_set(self.profiles, profile)
        profile_path = self.profiles / f"{profile['id']}.json"
        profile["displayName"] = "Tampered"
        profile_path.write_text(json.dumps(profile), encoding="utf-8")

        with self.assertRaisesRegex(validator.ProfileValidationError, "content hash mismatch"):
            validator.profile_contract(self.profiles)

    def test_paired_contract_requires_complete_target_and_metrics(self) -> None:
        profile = profile_payload()
        write_profile_set(self.profiles, profile)

        missing_target = validator.paired(self.profiles, self.source, self.target)
        self.assertFalse(missing_target["passed"])

        target_path = self.target / "NORITSU" / "color nega" / "test-roll" / "frame-1.tif"
        target_path.parent.mkdir(parents=True)
        target_path.write_bytes(b"paired target fixture")

        missing_metrics = validator.paired(self.profiles, self.source, self.target)
        self.assertFalse(missing_metrics["passed"])

        metrics_path = (
            self.source
            / "NORITSU"
            / "color nega"
            / "test-roll"
            / "frame-1"
            / "metrics.json"
        )
        metrics_path.parent.mkdir(parents=True)
        metrics_path.write_text(
            json.dumps(
                {
                    "mean_delta_e2000": 2.0,
                    "neutral_a_shift": 0.5,
                    "neutral_b_shift": 0.5,
                }
            ),
            encoding="utf-8",
        )

        report = validator.paired(self.profiles, self.source, self.target)

        self.assertTrue(report["passed"])
        self.assertEqual(report["failedProfiles"], 0)
        self.assertEqual(report["gateScope"], "coverage-and-smoke-only")
        self.assertFalse(report["qualifiesPairedValidated"])
        self.assertTrue(report["profiles"][0]["coverageSmokePassed"])

    def test_bundled_scanner_profiles_satisfy_contract(self) -> None:
        bundled_profiles = REPOSITORY_ROOT / "Sources" / "Chromabase" / "ScannerProfiles"
        manifest = json.loads((bundled_profiles / "manifest.json").read_text(encoding="utf-8"))

        report = validator.profile_contract(bundled_profiles)

        self.assertTrue(report["passed"])
        self.assertGreater(report["profileCount"], 0)
        self.assertEqual(report["profileCount"], manifest["profileCount"])
        self.assertEqual(sum(report["statusCounts"].values()), report["profileCount"])


if __name__ == "__main__":
    unittest.main()
