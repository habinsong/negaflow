#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path


# git 검사는 저장소 전체를 훑어야 하므로 기준을 저장소 루트에 둔다. macOS 트리는
# negaflow-mac/, Windows 트리는 negaflow-windows/ 아래에 있다.
REPO_ROOT = Path(__file__).resolve().parents[3]
ROOT = REPO_ROOT
MAC_ROOT = REPO_ROOT / "negaflow-mac"
MANIFEST = MAC_ROOT / "Config/bundled-resource-provenance-v1.json"
WINDOWS_NATIVE_SOURCE_ROOTS = (
    Path("negaflow-windows/src"),
    Path("negaflow-windows/tests"),
)
WINDOWS_THIRD_PARTY_MANIFEST_ROOT = Path("negaflow-windows/third_party/manifest")
LIBRAW_PREVIEW_BRIDGE = Path("negaflow-mac/scripts/libraw/native-preview-bridge.cpp")


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
    """번들 리소스 목록. 경로는 **macOS 트리 기준**이다.

    매니페스트가 `negaflow-mac/Config/` 에 있으므로 그 안의 경로도 같은 기준으로
    읽는다. 저장소 루트 기준으로 바꾸면 트리를 옮길 때마다 매니페스트 전체가
    같이 흔들린다.
    """
    roots = [
        MAC_ROOT / "Sources/ScannerKit/Resources",
        MAC_ROOT / "Sources/Chromabase/Presets",
        MAC_ROOT / "Sources/Chromabase/ScannerProfiles",
    ]
    paths = {
        path.relative_to(MAC_ROOT).as_posix()
        for directory in roots
        for path in directory.iterdir()
        if path.is_file()
    }
    paths.update(
        path.relative_to(MAC_ROOT).as_posix()
        for path in (MAC_ROOT / "Sources/negaflowApp/Resources").iterdir()
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
        digest = hashlib.sha256((MAC_ROOT / relative).read_bytes()).hexdigest()
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
        if (path.suffix.lower() in compiled_source_suffixes
                and not is_windows_native_source and relative != LIBRAW_PREVIEW_BRIDGE):
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

    package = (MAC_ROOT / "Package.swift").read_text(encoding="utf-8")
    for marker in (".package(", ".binaryTarget(", ".systemLibrary("):
        if marker in package:
            fail(f"Package.swift contains an external dependency surface: {marker}")
    return text_count, binary_count


def declared_windows_source_copyrights() -> dict[str, str]:
    manifest_path = ROOT / WINDOWS_THIRD_PARTY_MANIFEST_ROOT / "components.json"
    if not manifest_path.is_file():
        return {}
    try:
        document = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        fail(f"windows component manifest cannot be read: {error}")
    declared: dict[str, str] = {}
    for component in document.get("components", []):
        local_path = component.get("local_path")
        copyright_notice = component.get("copyright")
        if isinstance(local_path, str) and isinstance(copyright_notice, str):
            normalized = (Path("negaflow-windows") / local_path).as_posix()
            declared[normalized] = copyright_notice.lower()
    return declared


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
        "negaflow-mac/scripts/ci/verify-boundaries.sh",
        "negaflow-mac/scripts/ci/verify-provenance.py",
        "negaflow-mac/scripts/tests/test_ci_gate.py",
    }
    declared_copyrights = declared_windows_source_copyrights()
    candidates = []
    for root_name in (
        "negaflow-mac/Sources",
        "negaflow-mac/Tests",
        "negaflow-mac/scripts",
        "negaflow-windows/src",
        "negaflow-windows/tests",
        "negaflow-windows/scripts",
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
        if relative == LIBRAW_PREVIEW_BRIDGE.as_posix():
            if not text.startswith("// spdx-license-identifier: cddl-1.0\n// copyright 2026 negaflow contributors."):
                fail("LibRaw preview bridge must retain its CDDL notice and Negaflow authorship")
            if '#include "libraw/libraw.h"' not in text:
                fail("LibRaw preview bridge must use the upstream public header")
            continue
        if "spdx-license-identifier" in text:
            fail(f"unexpected third-party source header found in {relative}")
        if "copyright (c)" in text:
            expected_copyright = declared_copyrights.get(relative)
            if (
                not expected_copyright
                or expected_copyright not in text
                or text.count("copyright (c)") != 1
            ):
                fail(f"unexpected third-party source header found in {relative}")

    release_scripts = "\n".join(
        (MAC_ROOT / relative).read_text(encoding="utf-8").lower()
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
        (MAC_ROOT / "Config/defect-corpus-film-r-v2.json").read_text(encoding="utf-8")
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
    pattern_args = [arg for marker in forbidden for arg in ("-e", marker)]
    for offset in range(0, len(commits), 64):
        result = subprocess.run(
            [
                "git", "grep", "-I", "-i", "-n", "-F",
                *pattern_args,
                *commits[offset:offset + 64], "--",
                "Sources", "Tests",
                "negaflow-mac/Sources", "negaflow-mac/Tests",
                "negaflow-windows/src", "negaflow-windows/tests",
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
