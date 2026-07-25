#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# ///
"""Fail-closed validation for Negaflow scanner profile resources."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from collections import Counter
from pathlib import Path
from typing import Final, TypeAlias

JsonScalar: TypeAlias = None | bool | int | float | str
JsonValue: TypeAlias = JsonScalar | list["JsonValue"] | dict[str, "JsonValue"]
JsonObject: TypeAlias = dict[str, JsonValue]

PROFILE_SCHEMA_VERSION: Final[int] = 2
PROFILE_ID_PATTERN: Final[re.Pattern[str]] = re.compile(r"^[a-z0-9][a-z0-9_-]*$")
SHA256_PATTERN: Final[re.Pattern[str]] = re.compile(r"^sha256:[0-9a-f]{64}$")
VALIDATION_STATUSES: Final[frozenset[str]] = frozenset({
    "draft",
    "realOnly",
    "pairedSmoke",
    "pairedValidated",
})
SOURCE_KEYS: Final[frozenset[str]] = frozenset({
    "profile_metadata",
    "image_count",
    "tone",
    "coarse_zones",
    "fine_zones",
    "hue_bins",
    "neutral_axis",
    "texture",
    "scene_buckets",
    "coverage_candidates",
    "representative_candidates",
    "cut_summaries",
})
PROFILE_KEYS: Final[frozenset[str]] = frozenset({
    "schemaVersion",
    "id",
    "displayName",
    "scanner",
    "kind",
    "filmKey",
    "validationStatus",
    "rollCount",
    "imageCount",
    "singleRollLimited",
    "sourceProfiles",
    "tone",
    "color",
    "neutralAxis",
    "neutralAxisBins",
    "texture",
    "sceneBuckets",
    "coverageCandidates",
    "profileHash",
})
STAT_KEYS: Final[frozenset[str]] = frozenset({
    "count",
    "mean",
    "median",
    "p10",
    "p90",
    "min",
    "max",
})
CANDIDATE_KEYS: Final[frozenset[str]] = frozenset({
    "stem",
    "realFile",
    "p50",
    "contrastP90P10",
    "midChroma",
})
# 기존 로컬 검증기의 느슨한 회귀 임계값을 그대로 보존한다. 이 값은 coverage 산출물이
# 명백히 깨지지 않았는지 확인하는 smoke 전용이며 pairedValidated 승격/릴리즈 품질 기준이 아니다.
COVERAGE_SMOKE_LIMITS: Final[dict[str, float]] = {
    "median_delta_e2000": 8.0,
    "p90_delta_e2000": 18.0,
    "neutral_chroma_shift": 4.0,
}


class ProfileValidationError(RuntimeError):
    pass


def reject_constant(value: str) -> None:
    raise ProfileValidationError(f"non-standard JSON constant: {value}")


def read_json(path: Path) -> JsonObject:
    try:
        data = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    except OSError as error:
        raise ProfileValidationError(f"cannot read {path}: {error}") from error
    except json.JSONDecodeError as error:
        raise ProfileValidationError(f"invalid JSON {path}: {error}") from error
    if not isinstance(data, dict):
        raise ProfileValidationError(f"expected object: {path}")
    if not finite_walk(data):
        raise ProfileValidationError(f"non-finite numeric value: {path}")
    return data


def finite_walk(value: JsonValue) -> bool:
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, list):
        return all(finite_walk(item) for item in value)
    if isinstance(value, dict):
        return all(finite_walk(child) for child in value.values())
    return True


def require_keys(value: JsonObject, keys: frozenset[str], label: str) -> None:
    missing = sorted(keys.difference(value))
    if missing:
        raise ProfileValidationError(f"{label}: missing {','.join(missing)}")


def as_list(value: JsonValue, label: str = "value") -> list[JsonValue]:
    if isinstance(value, list):
        return value
    raise ProfileValidationError(f"{label}: expected list")


def as_object(value: JsonValue, label: str = "value") -> JsonObject:
    if isinstance(value, dict):
        return value
    raise ProfileValidationError(f"{label}: expected object")


def as_str(value: JsonValue, label: str = "value") -> str:
    if isinstance(value, str):
        return value
    raise ProfileValidationError(f"{label}: expected string")


def nonempty_str(value: JsonValue, label: str) -> str:
    result = as_str(value, label)
    if not result.strip():
        raise ProfileValidationError(f"{label}: expected non-empty string")
    return result


def as_int(value: JsonValue, label: str) -> int:
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    raise ProfileValidationError(f"{label}: expected integer")


def as_bool(value: JsonValue, label: str) -> bool:
    if isinstance(value, bool):
        return value
    raise ProfileValidationError(f"{label}: expected boolean")


def as_number(value: JsonValue, label: str) -> float:
    if isinstance(value, int | float) and not isinstance(value, bool):
        result = float(value)
        if math.isfinite(result):
            return result
    raise ProfileValidationError(f"{label}: expected finite number")


def validate_stat_map(value: JsonValue, label: str) -> None:
    mapping = as_object(value, label)
    if not mapping:
        raise ProfileValidationError(f"{label}: expected non-empty stat map")
    for name, raw_stat in mapping.items():
        stat_label = f"{label}.{name}"
        stat = as_object(raw_stat, stat_label)
        require_keys(stat, STAT_KEYS, stat_label)
        for key in STAT_KEYS:
            numeric = as_number(stat.get(key), f"{stat_label}.{key}")
            if key == "count" and numeric < 0:
                raise ProfileValidationError(f"{stat_label}.count: expected non-negative number")


def validate_candidate(value: JsonValue, label: str) -> None:
    candidate = as_object(value, label)
    require_keys(candidate, CANDIDATE_KEYS, label)
    nonempty_str(candidate.get("stem"), f"{label}.stem")
    nonempty_str(candidate.get("realFile"), f"{label}.realFile")
    for key in ("p50", "contrastP90P10", "midChroma"):
        as_number(candidate.get(key), f"{label}.{key}")


def validate_profile(profile: JsonObject, path: Path) -> tuple[str, str]:
    label = str(path)
    require_keys(profile, PROFILE_KEYS, label)

    schema_version = as_int(profile.get("schemaVersion"), f"{label}.schemaVersion")
    if schema_version != PROFILE_SCHEMA_VERSION:
        raise ProfileValidationError(
            f"{label}.schemaVersion: expected {PROFILE_SCHEMA_VERSION}, got {schema_version}"
        )

    profile_id = nonempty_str(profile.get("id"), f"{label}.id")
    if PROFILE_ID_PATTERN.fullmatch(profile_id) is None:
        raise ProfileValidationError(f"{label}.id: invalid profile identifier {profile_id!r}")
    if path.stem != profile_id:
        raise ProfileValidationError(
            f"{label}.id: filename stem {path.stem!r} does not match {profile_id!r}"
        )

    for key in ("displayName", "scanner", "kind", "filmKey"):
        nonempty_str(profile.get(key), f"{label}.{key}")

    status = nonempty_str(profile.get("validationStatus"), f"{label}.validationStatus")
    if status not in VALIDATION_STATUSES:
        allowed = ",".join(sorted(VALIDATION_STATUSES))
        raise ProfileValidationError(
            f"{label}.validationStatus: unsupported {status!r}; expected one of {allowed}"
        )

    roll_count = as_int(profile.get("rollCount"), f"{label}.rollCount")
    image_count = as_int(profile.get("imageCount"), f"{label}.imageCount")
    if roll_count < 1:
        raise ProfileValidationError(f"{label}.rollCount: expected at least 1")
    if image_count < 1:
        raise ProfileValidationError(f"{label}.imageCount: expected at least 1")
    single_roll_limited = as_bool(
        profile.get("singleRollLimited"), f"{label}.singleRollLimited"
    )
    if single_roll_limited != (roll_count < 2):
        raise ProfileValidationError(
            f"{label}.singleRollLimited: inconsistent with rollCount {roll_count}"
        )

    source_profiles = as_list(profile.get("sourceProfiles"), f"{label}.sourceProfiles")
    if len(source_profiles) != roll_count:
        raise ProfileValidationError(
            f"{label}.sourceProfiles: expected {roll_count} entries, got {len(source_profiles)}"
        )
    for index, source_profile in enumerate(source_profiles):
        nonempty_str(source_profile, f"{label}.sourceProfiles[{index}]")

    for key in ("tone", "color", "neutralAxis", "texture"):
        validate_stat_map(profile.get(key), f"{label}.{key}")

    neutral_bins = as_list(profile.get("neutralAxisBins"), f"{label}.neutralAxisBins")
    for index, raw_bin in enumerate(neutral_bins):
        bin_label = f"{label}.neutralAxisBins[{index}]"
        row = as_object(raw_bin, bin_label)
        require_keys(
            row,
            frozenset({"lumaCenter", "coveragePct", "labA", "labB"}),
            bin_label,
        )
        for key in ("lumaCenter", "coveragePct", "labA", "labB"):
            as_number(row.get(key), f"{bin_label}.{key}")

    if "hueResponse" in profile:
        hue_response = as_list(profile.get("hueResponse"), f"{label}.hueResponse")
        for index, raw_bin in enumerate(hue_response):
            bin_label = f"{label}.hueResponse[{index}]"
            row = as_object(raw_bin, bin_label)
            require_keys(
                row,
                frozenset({"labHueDegrees", "chromaGain", "hueRotateDegrees", "weight"}),
                bin_label,
            )
            for key in ("labHueDegrees", "chromaGain", "hueRotateDegrees", "weight"):
                as_number(row.get(key), f"{bin_label}.{key}")

    scene_buckets = as_list(profile.get("sceneBuckets"), f"{label}.sceneBuckets")
    for index, raw_bucket in enumerate(scene_buckets):
        bucket_label = f"{label}.sceneBuckets[{index}]"
        bucket = as_object(raw_bucket, bucket_label)
        require_keys(
            bucket,
            frozenset({
                "family",
                "name",
                "imageCount",
                "tone",
                "color",
                "texture",
                "representativeCandidates",
            }),
            bucket_label,
        )
        nonempty_str(bucket.get("family"), f"{bucket_label}.family")
        nonempty_str(bucket.get("name"), f"{bucket_label}.name")
        bucket_count = as_int(bucket.get("imageCount"), f"{bucket_label}.imageCount")
        if bucket_count < 0:
            raise ProfileValidationError(f"{bucket_label}.imageCount: expected non-negative integer")
        for key in ("tone", "color", "texture"):
            validate_stat_map(bucket.get(key), f"{bucket_label}.{key}")
        candidates = as_list(
            bucket.get("representativeCandidates"),
            f"{bucket_label}.representativeCandidates",
        )
        for candidate_index, candidate in enumerate(candidates):
            validate_candidate(
                candidate,
                f"{bucket_label}.representativeCandidates[{candidate_index}]",
            )

    coverage = as_list(profile.get("coverageCandidates"), f"{label}.coverageCandidates")
    for index, raw_axis in enumerate(coverage):
        axis_label = f"{label}.coverageCandidates[{index}]"
        axis = as_object(raw_axis, axis_label)
        require_keys(axis, frozenset({"axis", "candidates"}), axis_label)
        nonempty_str(axis.get("axis"), f"{axis_label}.axis")
        candidates = as_list(axis.get("candidates"), f"{axis_label}.candidates")
        for candidate_index, candidate in enumerate(candidates):
            validate_candidate(candidate, f"{axis_label}.candidates[{candidate_index}]")

    recorded_hash = nonempty_str(profile.get("profileHash"), f"{label}.profileHash")
    if SHA256_PATTERN.fullmatch(recorded_hash) is None:
        raise ProfileValidationError(f"{label}.profileHash: expected sha256:<64 lowercase hex>")
    actual_hash = canonical_profile_hash(profile)
    if recorded_hash != actual_hash:
        raise ProfileValidationError(
            f"{label}.profileHash: content hash mismatch; expected {actual_hash}"
        )
    return profile_id, recorded_hash


def canonical_profile_hash(profile: JsonObject) -> str:
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


def load_profiles(profiles_path: Path) -> list[JsonObject]:
    if not profiles_path.is_dir():
        raise ProfileValidationError(f"profile directory does not exist: {profiles_path}")

    manifest_path = profiles_path / "manifest.json"
    manifest = read_json(manifest_path)
    require_keys(
        manifest,
        frozenset({"schemaVersion", "profileCount", "profiles"}),
        str(manifest_path),
    )
    schema_version = as_int(
        manifest.get("schemaVersion"), f"{manifest_path}.schemaVersion"
    )
    if schema_version != PROFILE_SCHEMA_VERSION:
        raise ProfileValidationError(
            f"{manifest_path}.schemaVersion: expected {PROFILE_SCHEMA_VERSION}, got {schema_version}"
        )

    profile_count = as_int(manifest.get("profileCount"), f"{manifest_path}.profileCount")
    entries = as_list(manifest.get("profiles"), f"{manifest_path}.profiles")
    if profile_count < 1 or not entries:
        raise ProfileValidationError(f"{manifest_path}: profile set must not be empty")
    if profile_count != len(entries):
        raise ProfileValidationError(
            f"{manifest_path}.profileCount: expected {len(entries)}, got {profile_count}"
        )

    manifest_hashes: dict[str, str] = {}
    manifest_file_hashes: dict[str, str] = {}
    for index, raw_entry in enumerate(entries):
        entry_label = f"{manifest_path}.profiles[{index}]"
        entry = as_object(raw_entry, entry_label)
        require_keys(entry, frozenset({"id", "profileHash", "fileSHA256"}), entry_label)
        profile_id = nonempty_str(entry.get("id"), f"{entry_label}.id")
        if PROFILE_ID_PATTERN.fullmatch(profile_id) is None:
            raise ProfileValidationError(f"{entry_label}.id: invalid profile identifier {profile_id!r}")
        profile_hash = nonempty_str(entry.get("profileHash"), f"{entry_label}.profileHash")
        if SHA256_PATTERN.fullmatch(profile_hash) is None:
            raise ProfileValidationError(
                f"{entry_label}.profileHash: expected sha256:<64 lowercase hex>"
            )
        file_hash = nonempty_str(entry.get("fileSHA256"), f"{entry_label}.fileSHA256")
        if SHA256_PATTERN.fullmatch(file_hash) is None:
            raise ProfileValidationError(
                f"{entry_label}.fileSHA256: expected sha256:<64 lowercase hex>"
            )
        if profile_id in manifest_hashes:
            raise ProfileValidationError(f"{manifest_path}: duplicate profile id {profile_id!r}")
        manifest_hashes[profile_id] = profile_hash
        manifest_file_hashes[profile_id] = file_hash

    profile_paths = sorted(
        path for path in profiles_path.glob("*.json") if path.name != "manifest.json"
    )
    if not profile_paths:
        raise ProfileValidationError(f"{profiles_path}: no profile JSON files")
    file_ids = {path.stem for path in profile_paths}
    manifest_ids = set(manifest_hashes)
    if file_ids != manifest_ids:
        missing_files = sorted(manifest_ids.difference(file_ids))
        unlisted_files = sorted(file_ids.difference(manifest_ids))
        raise ProfileValidationError(
            f"{manifest_path}: manifest/file ID mismatch; "
            f"missingFiles={missing_files}, unlistedFiles={unlisted_files}"
        )
    if profile_count != len(profile_paths):
        raise ProfileValidationError(
            f"{manifest_path}.profileCount: expected {len(profile_paths)} profile files, got {profile_count}"
        )

    result: list[JsonObject] = []
    for path in profile_paths:
        profile = read_json(path)
        profile_id, profile_hash = validate_profile(profile, path)
        if manifest_hashes[profile_id] != profile_hash:
            raise ProfileValidationError(
                f"{manifest_path}: hash for {profile_id!r} does not match profile"
            )
        actual_file_hash = f"sha256:{hashlib.sha256(path.read_bytes()).hexdigest()}"
        if manifest_file_hashes[profile_id] != actual_file_hash:
            raise ProfileValidationError(
                f"{manifest_path}: file hash for {profile_id!r} does not match profile bytes"
            )
        result.append(profile)
    return result


def source_contract(source: Path) -> JsonObject:
    index_path = source / "film_index.json"
    index = read_json(index_path)
    files = sorted(source.rglob("*.json")) if source.is_dir() else []
    bad: list[str] = []
    profiles: list[Path] = []
    profile_payloads: dict[str, JsonObject] = {}
    for path in files:
        try:
            payload = read_json(path)
            if path.name == "profile.json":
                profiles.append(path)
                relative_path = path.relative_to(source).as_posix()
                profile_payloads[relative_path] = payload
                missing = sorted(SOURCE_KEYS.difference(payload))
                if missing:
                    bad.append(f"{path}: missing {','.join(missing)}")
        except ProfileValidationError as error:
            bad.append(str(error))

    try:
        index_summary = validate_source_index(index, index_path, source, profile_payloads)
    except ProfileValidationError as error:
        bad.append(str(error))
        index_summary = {
            "declaredProfiles": 0,
            "groups": 0,
            "totalImages": 0,
        }
    return {
        "mode": "source-contract",
        "jsonFiles": len(files),
        "rollProfiles": len(profiles),
        "declaredProfiles": index_summary["declaredProfiles"],
        "groups": index_summary["groups"],
        "totalImages": index_summary["totalImages"],
        "badCount": len(bad),
        "bad": bad[:20],
        "passed": len(bad) == 0 and bool(profiles),
    }


def validate_source_index(
    index: JsonObject,
    index_path: Path,
    source: Path,
    profile_payloads: dict[str, JsonObject],
) -> JsonObject:
    label = str(index_path)
    require_keys(index, frozenset({"profile_count", "groups", "profiles"}), label)
    declared_count = as_int(index.get("profile_count"), f"{label}.profile_count")
    raw_profiles = as_list(index.get("profiles"), f"{label}.profiles")
    raw_groups = as_list(index.get("groups"), f"{label}.groups")
    if declared_count < 1 or not raw_profiles or not raw_groups:
        raise ProfileValidationError(f"{label}: source index must not be empty")
    if declared_count != len(raw_profiles):
        raise ProfileValidationError(
            f"{label}.profile_count: expected {len(raw_profiles)}, got {declared_count}"
        )

    rows_by_path: dict[str, tuple[tuple[str, str, str], int]] = {}
    total_images = 0
    for index_number, raw_row in enumerate(raw_profiles):
        row_label = f"{label}.profiles[{index_number}]"
        row = as_object(raw_row, row_label)
        require_keys(
            row,
            frozenset({
                "scanner",
                "kind",
                "film_roll",
                "film_key",
                "roll",
                "profile_path",
                "image_count",
                "failed_count",
            }),
            row_label,
        )
        scanner = nonempty_str(row.get("scanner"), f"{row_label}.scanner")
        kind = nonempty_str(row.get("kind"), f"{row_label}.kind")
        film_roll = nonempty_str(row.get("film_roll"), f"{row_label}.film_roll")
        film_key = nonempty_str(row.get("film_key"), f"{row_label}.film_key")
        roll = nonempty_str(row.get("roll"), f"{row_label}.roll")
        relative_path = source_profile_relative_path(
            source,
            nonempty_str(row.get("profile_path"), f"{row_label}.profile_path"),
            f"{row_label}.profile_path",
        )
        image_count = as_int(row.get("image_count"), f"{row_label}.image_count")
        failed_count = as_int(row.get("failed_count"), f"{row_label}.failed_count")
        if image_count < 1 or failed_count < 0:
            raise ProfileValidationError(
                f"{row_label}: image_count must be positive and failed_count non-negative"
            )
        if relative_path in rows_by_path:
            raise ProfileValidationError(f"{label}: duplicate profile_path {relative_path!r}")
        rows_by_path[relative_path] = ((scanner, kind, film_key), image_count)
        total_images += image_count

        payload = profile_payloads.get(relative_path)
        if payload is None:
            continue
        metadata = as_object(payload.get("profile_metadata"), f"{relative_path}.profile_metadata")
        expected_metadata = {
            "scanner": scanner,
            "kind": kind,
            "film_roll": film_roll,
            "film_key": film_key,
        }
        for key, expected in expected_metadata.items():
            actual = nonempty_str(metadata.get(key), f"{relative_path}.profile_metadata.{key}")
            if actual != expected:
                raise ProfileValidationError(
                    f"{relative_path}.profile_metadata.{key}: expected {expected!r}, got {actual!r}"
                )
        if nonempty_str(payload.get("roll"), f"{relative_path}.roll") != roll:
            raise ProfileValidationError(f"{relative_path}.roll: does not match film_index")
        if as_int(payload.get("image_count"), f"{relative_path}.image_count") != image_count:
            raise ProfileValidationError(f"{relative_path}.image_count: does not match film_index")
        failed_images = as_list(payload.get("failed_images"), f"{relative_path}.failed_images")
        if len(failed_images) != failed_count:
            raise ProfileValidationError(f"{relative_path}.failed_images: does not match failed_count")

    actual_paths = set(profile_payloads)
    declared_paths = set(rows_by_path)
    if actual_paths != declared_paths:
        missing = sorted(declared_paths.difference(actual_paths))
        unlisted = sorted(actual_paths.difference(declared_paths))
        raise ProfileValidationError(
            f"{label}: profile path mismatch; missing={missing}, unlisted={unlisted}"
        )
    if declared_count != len(actual_paths):
        raise ProfileValidationError(
            f"{label}.profile_count: expected {len(actual_paths)} actual profiles, got {declared_count}"
        )

    group_keys: set[tuple[str, str, str]] = set()
    grouped_path_counts: Counter[str] = Counter()
    for group_index, raw_group in enumerate(raw_groups):
        group_label = f"{label}.groups[{group_index}]"
        group = as_object(raw_group, group_label)
        require_keys(
            group,
            frozenset({"scanner", "kind", "film_key", "roll_count", "image_count", "profiles"}),
            group_label,
        )
        group_key = (
            nonempty_str(group.get("scanner"), f"{group_label}.scanner"),
            nonempty_str(group.get("kind"), f"{group_label}.kind"),
            nonempty_str(group.get("film_key"), f"{group_label}.film_key"),
        )
        if group_key in group_keys:
            raise ProfileValidationError(f"{label}: duplicate group {group_key!r}")
        group_keys.add(group_key)
        roll_count = as_int(group.get("roll_count"), f"{group_label}.roll_count")
        group_image_count = as_int(group.get("image_count"), f"{group_label}.image_count")
        raw_paths = as_list(group.get("profiles"), f"{group_label}.profiles")
        group_paths = [
            source_profile_relative_path(
                source,
                nonempty_str(raw_path, f"{group_label}.profiles[{path_index}]"),
                f"{group_label}.profiles[{path_index}]",
            )
            for path_index, raw_path in enumerate(raw_paths)
        ]
        if roll_count < 1 or roll_count != len(group_paths):
            raise ProfileValidationError(
                f"{group_label}.roll_count: expected {len(group_paths)}, got {roll_count}"
            )
        if len(set(group_paths)) != len(group_paths):
            raise ProfileValidationError(f"{group_label}.profiles: duplicate profile path")
        group_total = 0
        for relative_path in group_paths:
            row = rows_by_path.get(relative_path)
            if row is None:
                raise ProfileValidationError(
                    f"{group_label}.profiles: undeclared profile {relative_path!r}"
                )
            row_group_key, row_image_count = row
            if row_group_key != group_key:
                raise ProfileValidationError(
                    f"{group_label}.profiles: {relative_path!r} belongs to {row_group_key!r}"
                )
            grouped_path_counts[relative_path] += 1
            group_total += row_image_count
        if group_image_count != group_total:
            raise ProfileValidationError(
                f"{group_label}.image_count: expected {group_total}, got {group_image_count}"
            )

    if set(grouped_path_counts) != declared_paths or any(
        count != 1 for count in grouped_path_counts.values()
    ):
        missing = sorted(declared_paths.difference(grouped_path_counts))
        repeated = sorted(path for path, count in grouped_path_counts.items() if count != 1)
        raise ProfileValidationError(
            f"{label}.groups: each profile must appear exactly once; missing={missing}, repeated={repeated}"
        )

    return {
        "declaredProfiles": declared_count,
        "groups": len(raw_groups),
        "totalImages": total_images,
    }


def source_profile_relative_path(source: Path, raw_path: str, label: str) -> str:
    declared = Path(raw_path)
    if declared.is_absolute() or ".." in declared.parts:
        raise ProfileValidationError(f"{label}: expected safe relative path")
    source_root = source.resolve()
    candidate = (source.parent / declared).resolve()
    try:
        return candidate.relative_to(source_root).as_posix()
    except ValueError as error:
        raise ProfileValidationError(f"{label}: path escapes source directory") from error


def profile_contract(profiles_path: Path) -> JsonObject:
    profiles = load_profiles(profiles_path)
    statuses = Counter(as_str(profile.get("validationStatus")) for profile in profiles)
    return {
        "mode": "profile-contract",
        "profileCount": len(profiles),
        "statusCounts": dict(sorted(statuses.items())),
        "passed": bool(profiles),
    }


def target_stems(target: Path) -> set[str]:
    stems: set[str] = set()
    if not target.is_dir():
        return stems
    for path in target.rglob("*"):
        if path.is_file():
            relative_stem = path.relative_to(target).with_suffix("").as_posix()
            stems.add(relative_stem)
            stems.add(path.stem)
    return stems


def candidate_alias_groups(profile: JsonObject) -> list[set[str]]:
    groups: list[set[str]] = []
    seen: set[str] = set()
    for raw_axis in as_list(profile.get("coverageCandidates"), "coverageCandidates"):
        axis = as_object(raw_axis, "coverageCandidates[]")
        for raw_candidate in as_list(axis.get("candidates"), "coverageCandidates[].candidates"):
            candidate = as_object(raw_candidate, "coverageCandidates[].candidates[]")
            stem = as_str(candidate.get("stem"), "candidate.stem")
            real_file = as_str(candidate.get("realFile"), "candidate.realFile")
            if stem in seen:
                continue
            seen.add(stem)
            groups.append({stem, Path(real_file).with_suffix("").as_posix(), Path(real_file).stem})
    return groups


def source_metrics_for(profile: JsonObject, source: Path) -> list[JsonObject]:
    metrics: list[JsonObject] = []
    seen: set[Path] = set()
    for aliases in candidate_alias_groups(profile):
        for stem in sorted(aliases):
            metrics_path = source / stem / "metrics.json"
            if metrics_path in seen or not metrics_path.is_file():
                continue
            seen.add(metrics_path)
            metrics.append(read_json(metrics_path))
    return metrics


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    pos = (len(ordered) - 1) * pct
    low = math.floor(pos)
    high = math.ceil(pos)
    if low == high:
        return ordered[low]
    return ordered[low] * (1 - (pos - low)) + ordered[high] * (pos - low)


def metric_value(row: JsonObject, key: str) -> float | None:
    value = row.get(key)
    if isinstance(value, int | float) and not isinstance(value, bool):
        numeric = float(value)
        if math.isfinite(numeric):
            return numeric
    return None


def paired(profiles_path: Path, source: Path, target: Path) -> JsonObject:
    """Run coverage + loose metric smoke checks only.

    Passing this function does not qualify a profile for pairedValidated and is not a
    release-quality gate. A separate versioned quality corpus must establish those claims.
    """
    profiles = load_profiles(profiles_path)
    stems = target_stems(target)
    rows: list[JsonObject] = []
    failed = 0
    for profile in profiles:
        required = candidate_alias_groups(profile)
        covered = [aliases for aliases in required if aliases.intersection(stems)]
        metrics = source_metrics_for(profile, source)
        delta = [
            value
            for metric in metrics
            if (value := metric_value(metric, "mean_delta_e2000")) is not None
        ]
        neutral_a = [
            value
            for metric in metrics
            if (value := metric_value(metric, "neutral_a_shift")) is not None
        ]
        neutral_b = [
            value
            for metric in metrics
            if (value := metric_value(metric, "neutral_b_shift")) is not None
        ]
        neutral = [math.hypot(a, b) for a, b in zip(neutral_a, neutral_b, strict=False)]
        median_delta = percentile(delta, 0.5)
        p90_delta = percentile(delta, 0.9)
        neutral_shift = percentile(neutral, 0.5)
        passed = bool(required) and len(covered) == len(required)
        passed = passed and len(metrics) >= len(required)
        passed = passed and len(delta) == len(metrics)
        passed = passed and len(neutral_a) == len(metrics) and len(neutral_b) == len(metrics)
        passed = passed and median_delta <= COVERAGE_SMOKE_LIMITS["median_delta_e2000"]
        passed = passed and p90_delta <= COVERAGE_SMOKE_LIMITS["p90_delta_e2000"]
        passed = passed and neutral_shift <= COVERAGE_SMOKE_LIMITS["neutral_chroma_shift"]
        if not passed:
            failed += 1
        rows.append({
            "id": profile["id"],
            "requiredCoverage": len(required),
            "covered": len(covered),
            "metricFiles": len(metrics),
            "medianDeltaE2000": median_delta,
            "p90DeltaE2000": p90_delta,
            "neutralChromaShift": neutral_shift,
            "coverageSmokePassed": passed,
            "passed": passed,
        })
    return {
        "mode": "paired",
        "gateScope": "coverage-and-smoke-only",
        "qualifiesPairedValidated": False,
        "profileCount": len(profiles),
        "failedProfiles": failed,
        "profiles": rows,
        "passed": bool(profiles) and failed == 0,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Validate Negaflow scanner profiles. Paired mode is a coverage smoke check, "
            "not a pairedValidated promotion or release-quality gate."
        )
    )
    parser.add_argument(
        "--mode",
        choices=("source-contract", "profile-contract", "paired"),
        required=True,
    )
    parser.add_argument("--source", type=Path, default=Path("LUT_target/SOURCE"))
    parser.add_argument(
        "--profiles",
        type=Path,
        default=Path("Sources/Chromabase/ScannerProfiles"),
    )
    parser.add_argument("--target", type=Path, default=Path("LUT_target/TARGET"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.mode == "source-contract":
            report = source_contract(args.source)
        elif args.mode == "profile-contract":
            report = profile_contract(args.profiles)
        else:
            report = paired(args.profiles, args.source, args.target)
    except ProfileValidationError as error:
        report = {"mode": args.mode, "errors": [str(error)], "passed": False}
        if args.mode == "paired":
            report["gateScope"] = "coverage-and-smoke-only"
            report["qualifiesPairedValidated"] = False
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False))
    return 0 if bool(report["passed"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
