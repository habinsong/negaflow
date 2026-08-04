#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "Config/bundled-resource-provenance-v1.json"
WINDOWS_NATIVE_SOURCE_ROOTS = (
    Path("Negaflow.Windows/src"),
    Path("Negaflow.Windows/tests"),
)
WINDOWS_THIRD_PARTY_MANIFEST_ROOT = Path("Negaflow.Windows/third_party/manifest")


def fail(message: str) -> None:
    print(f"[provenance] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def repository_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return [
        ROOT / entry.decode("utf-8")
        for entry in result.stdout.split(b"\0")
        if entry
    ]


def resource_files() -> set[str]:
    roots = [
        ROOT / "Sources/ScannerKit/Resources",
        ROOT / "Sources/Chromabase/Presets",
        ROOT / "Sources/Chromabase/ScannerProfiles",
    ]
    paths = {
        path.relative_to(ROOT).as_posix()
        for directory in roots
        for path in directory.iterdir()
        if path.is_file()
    }
    paths.update(
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "Sources/negaflowApp/Resources").iterdir()
        if path.is_file() and path.suffix.lower() in {".png", ".icns"}
    )
    return paths


def verify_resource_manifest() -> int:
    try:
        document = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"resource manifest cannot be read: {error}")
    if document.get("schemaVersion") != 1:
        fail("resource manifest schemaVersion must be 1")

    declared: dict[str, str] = {}
    for group in document.get("groups", []):
        if not group.get("origin") or not group.get("license"):
            fail(f"resource group lacks origin or license: {group.get('id')!r}")
        for entry in group.get("files", []):
            path = entry.get("path")
            digest = entry.get("sha256")
            if not isinstance(path, str) or not isinstance(digest, str):
                fail(f"invalid resource entry in group {group.get('id')!r}")
            if path in declared:
                fail(f"resource is declared more than once: {path}")
            declared[path] = digest

    actual = resource_files()
    missing = sorted(actual - declared.keys())
    stale = sorted(declared.keys() - actual)
    if missing:
        fail(f"resources lack provenance records: {', '.join(missing)}")
    if stale:
        fail(f"provenance records reference missing resources: {', '.join(stale)}")

    for relative, expected in sorted(declared.items()):
        digest = hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()
        if digest != expected:
            fail(f"resource hash changed without provenance review: {relative}")
    return len(declared)


def verify_tree_policy(files: list[Path]) -> tuple[int, int]:
    compiled_source_suffixes = {".c", ".cc", ".cpp", ".h", ".hpp", ".m", ".mm"}
    binary_suffixes = {
        ".a", ".dylib", ".so", ".framework", ".xcframework",
        ".zip", ".tar", ".gz", ".dmg", ".pkg",
    }
    vendor_names = {"vendor", "vendors", "third_party", "third-party"}
    binary_count = 0
    text_count = 0

    for path in files:
        relative = path.relative_to(ROOT)
        is_windows_native_source = any(
            relative.is_relative_to(root) for root in WINDOWS_NATIVE_SOURCE_ROOTS
        )
        if path.suffix.lower() in compiled_source_suffixes and not is_windows_native_source:
            fail(f"foreign/native source is not allowed in the Apache repository: {relative}")
        is_windows_component_manifest = (
            relative.parent == WINDOWS_THIRD_PARTY_MANIFEST_ROOT
            and relative.suffix.lower() == ".json"
        )
        if (
            any(part.lower() in vendor_names for part in relative.parts)
            and not is_windows_component_manifest
        ):
            fail(f"vendored directory is not allowed: {relative}")
        if path.suffix.lower() in binary_suffixes:
            fail(f"bundled executable/archive is not allowed: {relative}")
        data = path.read_bytes()
        if b"\0" in data[:8192]:
            binary_count += 1
        else:
            text_count += 1

    package = (ROOT / "Package.swift").read_text(encoding="utf-8")
    for marker in (".package(", ".binaryTarget(", ".systemLibrary("):
        if marker in package:
            fail(f"Package.swift contains an external dependency surface: {marker}")
    return text_count, binary_count


def verify_implementation_boundary() -> None:
    forbidden = (
        "darktable",
        "rawtherapee",
        "negadoctor",
        "sanei_",
        "scanimage",
        "libsane",
        "sane-backends",
        "sane_frame_ir",
        "gnu general public license",
    )
    excluded = {
        "scripts/ci/verify-boundaries.sh",
        "scripts/ci/verify-provenance.py",
        "scripts/tests/test_ci_gate.py",
    }
    candidates = []
    for root_name in (
        "Sources",
        "Tests",
        "scripts",
        "Negaflow.Windows/src",
        "Negaflow.Windows/tests",
        "Negaflow.Windows/scripts",
    ):
        candidates.extend((ROOT / root_name).rglob("*"))
    for path in candidates:
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT).as_posix()
        if relative in excluded or "__pycache__" in path.parts:
            continue
        try:
            text = path.read_text(encoding="utf-8").lower()
        except UnicodeDecodeError:
            continue
        for marker in forbidden:
            if marker in text:
                fail(f"external implementation marker {marker!r} found in {relative}")
        if "spdx-license-identifier" in text or "copyright (c)" in text:
            fail(f"unexpected third-party source header found in {relative}")

    release_scripts = "\n".join(
        (ROOT / relative).read_text(encoding="utf-8").lower()
        for relative in (
            "scripts/package-app.sh",
            "scripts/build-release.sh",
            "scripts/create-release-artifacts.sh",
        )
    )
    for marker in ("negaflow-scanner-sane", "scanimage", "sane-backends"):
        if marker in release_scripts:
            fail(f"main application release scripts bundle the scanner plugin: {marker}")


def verify_external_data_policy() -> None:
    corpus = json.loads(
        (ROOT / "Config/defect-corpus-film-r-v2.json").read_text(encoding="utf-8")
    )
    if corpus.get("doi") != "10.6084/m9.figshare.21803304.v2":
        fail("FILM-R corpus DOI is missing or unpinned")
    if corpus.get("license") != "CC BY 4.0":
        fail("FILM-R corpus license is missing or changed")
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
    if any(b"build/defect-corpus/" in path for path in tracked):
        fail("FILM-R image corpus must not be tracked or bundled")


def verify_reachable_history() -> int:
    commits = subprocess.check_output(
        ["git", "rev-list", "HEAD"],
        cwd=ROOT,
        text=True,
    ).splitlines()
    forbidden = (
        "darktable",
        "rawtherapee",
        "negadoctor",
        "sanei_",
        "sane_frame_ir",
        "software ice",
        "region ice",
        "infrared ice",
        "silverfast srdx 동일",
        "crnojevic",
    )
    pattern = "|".join(forbidden)
    for offset in range(0, len(commits), 64):
        result = subprocess.run(
            [
                "git", "grep", "-I", "-i", "-n", "-E", pattern,
                *commits[offset:offset + 64], "--",
                "Sources", "Tests",
                "Negaflow.Windows/src", "Negaflow.Windows/tests",
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if result.returncode not in (0, 1):
            fail(f"reachable history scan failed: {result.stderr.strip()}")
        if result.returncode == 0:
            first_match = result.stdout.splitlines()[0]
            fail(f"external implementation marker remains in reachable history: {first_match}")
    return len(commits)


def main() -> None:
    files = repository_files()
    resource_count = verify_resource_manifest()
    text_count, binary_count = verify_tree_policy(files)
    verify_implementation_boundary()
    verify_external_data_policy()
    history_count = verify_reachable_history()
    print(
        "[provenance] verified "
        f"files={len(files)} text={text_count} binary={binary_count} "
        f"declared_resources={resource_count} reachable_commits={history_count}"
    )


if __name__ == "__main__":
    main()
