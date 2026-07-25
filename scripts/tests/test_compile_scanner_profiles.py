from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import os
import sys
import tempfile
import unittest
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
COMPILER_PATH = REPOSITORY_ROOT / "scripts" / "compile_scanner_profiles.py"
SPEC = importlib.util.spec_from_file_location("compile_scanner_profiles", COMPILER_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Cannot import compiler: {COMPILER_PATH}")
compiler = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = compiler
SPEC.loader.exec_module(compiler)


def group(scanner: str, rolls: list[str], image_count: int = 40) -> Any:
    return compiler.GroupSpec(
        scanner=scanner,
        kind="color nega",
        film_key="test film",
        roll_count=len(rolls),
        image_count=image_count,
        profiles=tuple(
            f"SOURCE/{scanner}/color nega/{roll}/profile.json"
            for roll in rolls
        ),
    )


def hue_bins(saturation: float, hue_degrees: float) -> list[Any]:
    hue = compiler.HueBinAggregate(
        coverage=2.0,
        saturation=saturation,
        lab_a=math.cos(math.radians(hue_degrees)),
        lab_b=math.sin(math.radians(hue_degrees)),
    )
    return [hue] + [None] * (compiler.HUE_BIN_COUNT - 1)


def write_source_fixture(root: Path) -> tuple[Path, Path, Path]:
    source = root / "SOURCE"
    declared_path = "SOURCE/NORITSU/color nega/Test Roll/profile.json"
    profile_path = root / declared_path
    profile_path.parent.mkdir(parents=True)
    profile_path.write_text(
        json.dumps({
            "image_count": 1,
            "profile_metadata": {
                "scanner": "NORITSU",
                "kind": "color nega",
                "film_key": "test film",
            },
            "cut_summaries": [{}],
            "scene_buckets": {},
            "coverage_candidates": {},
            "neutral_axis": [],
            "hue_bins": [],
        }),
        encoding="utf-8",
    )
    (source / "film_index.json").write_text(
        json.dumps({
            "profile_count": 1,
            "groups": [{
                "scanner": "NORITSU",
                "kind": "color nega",
                "film_key": "test film",
                "roll_count": 1,
                "image_count": 1,
                "profiles": [declared_path],
            }],
            "profiles": [{
                "scanner": "NORITSU",
                "kind": "color nega",
                "film_key": "test film",
                "image_count": 1,
                "profile_path": declared_path,
            }],
        }),
        encoding="utf-8",
    )
    return source, source / "film_index.json", profile_path


class ScannerProfileCompilerTests(unittest.TestCase):
    def test_hue_response_accepts_only_exact_normalized_roll_label_set(self) -> None:
        noritsu = group("NORITSU", ["Roll A", "ROLL B"], image_count=76)
        frontier = group("SP-3000", ["roll b", "roll a"], image_count=75)

        responses = compiler.compute_hue_responses([
            (noritsu, hue_bins(0.4, 10.0)),
            (frontier, hue_bins(0.2, 20.0)),
        ])

        self.assertEqual(set(responses), {
            ("NORITSU", "color nega"),
            ("SP-3000", "color nega"),
        })

    def test_hue_response_rejects_similar_counts_with_different_roll_labels(self) -> None:
        noritsu = group("NORITSU", ["Roll A"], image_count=38)
        frontier = group("SP-3000", ["Roll B"], image_count=37)

        responses = compiler.compute_hue_responses([
            (noritsu, hue_bins(0.4, 10.0)),
            (frontier, hue_bins(0.2, 20.0)),
        ])

        self.assertEqual(responses, {})

    def test_compile_records_deterministic_profile_file_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source, _, _ = write_source_fixture(root)
            first_out = root / "first" / "profiles"
            first_resource = root / "first" / "resources"
            second_out = root / "second" / "profiles"
            second_resource = root / "second" / "resources"

            manifest = compiler.compile_profiles(source, first_out, first_resource)
            compiler.compile_profiles(source, second_out, second_resource)

            entry = manifest["profiles"][0]
            profile_path = first_out / f"{entry['id']}.json"
            expected = f"sha256:{hashlib.sha256(profile_path.read_bytes()).hexdigest()}"
            self.assertEqual(entry["fileSHA256"], expected)
            self.assertEqual(
                (first_out / "manifest.json").read_bytes(),
                (first_resource / "manifest.json").read_bytes(),
            )
            self.assertEqual(
                {path.name: path.read_bytes() for path in first_out.glob("*.json")},
                {path.name: path.read_bytes() for path in second_out.glob("*.json")},
            )
            self.assertEqual(
                {path.name: path.read_bytes() for path in first_resource.glob("*.json")},
                {path.name: path.read_bytes() for path in second_resource.glob("*.json")},
            )

    def test_compile_rejects_roll_metadata_or_count_that_disagrees_with_index(self) -> None:
        mutations = {
            "scanner": ("profile_metadata", "scanner", "SP-3000"),
            "kind": ("profile_metadata", "kind", "color slide"),
            "film_key": ("profile_metadata", "film_key", "other film"),
            "image_count": (None, "image_count", 2),
        }
        for field, (container, key, value) in mutations.items():
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary_directory:
                root = Path(temporary_directory)
                source, _, profile_path = write_source_fixture(root)
                payload = json.loads(profile_path.read_text(encoding="utf-8"))
                target = payload if container is None else payload[container]
                target[key] = value
                profile_path.write_text(json.dumps(payload), encoding="utf-8")

                with self.assertRaisesRegex(compiler.ProfileCompileError, "does not match film_index"):
                    compiler.compile_profiles(source, root / "out", None)

    def test_compile_rejects_index_group_identity_and_image_count_mismatch(self) -> None:
        mutations = {
            "scanner": "SP-3000",
            "kind": "color slide",
            "film_key": "other film",
        }
        for field, value in mutations.items():
            with self.subTest(field=field), tempfile.TemporaryDirectory() as temporary_directory:
                root = Path(temporary_directory)
                source, index_path, _ = write_source_fixture(root)
                index = json.loads(index_path.read_text(encoding="utf-8"))
                index["groups"][0][field] = value
                index_path.write_text(json.dumps(index), encoding="utf-8")

                with self.assertRaisesRegex(
                    compiler.ProfileCompileError,
                    "group (source provenance|identity)",
                ):
                    compiler.compile_profiles(source, root / "out", None)

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source, index_path, _ = write_source_fixture(root)
            index = json.loads(index_path.read_text(encoding="utf-8"))
            index["groups"][0]["image_count"] = 2
            index_path.write_text(json.dumps(index), encoding="utf-8")

            with self.assertRaisesRegex(compiler.ProfileCompileError, "group.image_count mismatch"):
                compiler.compile_profiles(source, root / "out", None)

    def test_compile_rejects_image_count_that_disagrees_with_actual_rows(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source, _, profile_path = write_source_fixture(root)
            payload = json.loads(profile_path.read_text(encoding="utf-8"))
            payload["cut_summaries"] = []
            profile_path.write_text(json.dumps(payload), encoding="utf-8")

            with self.assertRaisesRegex(compiler.ProfileCompileError, "actual cut_summaries"):
                compiler.compile_profiles(source, root / "out", None)

    def test_compile_rejects_unlisted_actual_roll_profile(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source, _, profile_path = write_source_fixture(root)
            unlisted = source / "NORITSU" / "color nega" / "Unlisted" / "profile.json"
            unlisted.parent.mkdir(parents=True)
            unlisted.write_bytes(profile_path.read_bytes())

            with self.assertRaisesRegex(compiler.ProfileCompileError, "unlisted"):
                compiler.compile_profiles(source, root / "out", None)

    def test_compile_rejects_lossy_profile_id_collision_before_writing(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source, index_path, first_path = write_source_fixture(root)
            index = json.loads(index_path.read_text(encoding="utf-8"))
            second_declared = "SOURCE/NORITSU/color nega/Second Roll/profile.json"
            second_path = root / second_declared
            second_path.parent.mkdir(parents=True)
            second_payload = json.loads(first_path.read_text(encoding="utf-8"))
            second_payload["profile_metadata"]["film_key"] = "test-film"
            second_path.write_text(json.dumps(second_payload), encoding="utf-8")
            index["profile_count"] = 2
            index["profiles"].append({
                "scanner": "NORITSU",
                "kind": "color nega",
                "film_key": "test-film",
                "image_count": 1,
                "profile_path": second_declared,
            })
            index["groups"].append({
                "scanner": "NORITSU",
                "kind": "color nega",
                "film_key": "test-film",
                "roll_count": 1,
                "image_count": 1,
                "profiles": [second_declared],
            })
            index_path.write_text(json.dumps(index), encoding="utf-8")
            out = root / "out"

            with self.assertRaisesRegex(compiler.ProfileCompileError, "lossy profile id collision"):
                compiler.compile_profiles(source, out, None)
            self.assertFalse(out.exists(), "collision validation must happen before output writes")

    def test_compile_removes_stale_json_from_both_output_directories(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source, _, _ = write_source_fixture(root)
            out = root / "out"
            resource = root / "resource"
            out.mkdir()
            resource.mkdir()
            (out / "stale.json").write_text("{}", encoding="utf-8")
            (resource / "stale.json").write_text("{}", encoding="utf-8")
            nested_stale = out / "old" / "nested.json"
            nested_stale.parent.mkdir()
            nested_stale.write_text("{}", encoding="utf-8")

            compiler.compile_profiles(source, out, resource)

            self.assertFalse((out / "stale.json").exists())
            self.assertFalse((resource / "stale.json").exists())
            self.assertFalse(nested_stale.exists())
            self.assertEqual(
                {path.name for path in out.glob("*.json")},
                {"manifest.json", "noritsu__color-nega__test-film.json"},
            )
            self.assertEqual(
                {path.name for path in resource.glob("*.json")},
                {"manifest.json", "noritsu__color-nega__test-film.json"},
            )

    def test_compile_replaces_expected_output_symlink_without_following_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source, _, _ = write_source_fixture(root)
            out = root / "out"
            out.mkdir()
            victim = root / "victim.json"
            victim.write_text('{"keep": true}\n', encoding="utf-8")
            expected = out / "noritsu__color-nega__test-film.json"
            expected.symlink_to(victim)

            compiler.compile_profiles(source, out, None)

            self.assertEqual(victim.read_text(encoding="utf-8"), '{"keep": true}\n')
            self.assertFalse(expected.is_symlink())
            self.assertTrue(expected.is_file())

    def test_compile_atomically_replaces_expected_output_hardlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source, _, _ = write_source_fixture(root)
            out = root / "out"
            out.mkdir()
            victim = root / "victim.json"
            victim.write_text('{"keep": true}\n', encoding="utf-8")
            expected = out / "noritsu__color-nega__test-film.json"
            os.link(victim, expected)

            compiler.compile_profiles(source, out, None)

            self.assertEqual(victim.read_text(encoding="utf-8"), '{"keep": true}\n')
            self.assertNotEqual(expected.stat().st_ino, victim.stat().st_ino)

    def test_portable_provenance_normalization_matches_swift_ascii_domain(self) -> None:
        self.assertEqual(
            compiler.normalized_provenance_component(" \tSP-3000\r\n"),
            "sp-3000",
        )
        with self.assertRaisesRegex(compiler.ProfileCompileError, "non-ASCII provenance"):
            compiler.normalized_provenance_component("Straße")

    def test_compile_enforces_portable_provenance_domain(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            source, index_path, old_profile_path = write_source_fixture(root)
            new_declared = "SOURCE/NORITSU/color nega/Test Röll/profile.json"
            new_profile_path = root / new_declared
            new_profile_path.parent.mkdir(parents=True)
            new_profile_path.write_bytes(old_profile_path.read_bytes())
            old_profile_path.unlink()
            index = json.loads(index_path.read_text(encoding="utf-8"))
            index["profiles"][0]["profile_path"] = new_declared
            index["groups"][0]["profiles"] = [new_declared]
            index_path.write_text(json.dumps(index), encoding="utf-8")

            with self.assertRaisesRegex(compiler.ProfileCompileError, "non-ASCII provenance"):
                compiler.compile_profiles(source, root / "out", None)


if __name__ == "__main__":
    unittest.main()
