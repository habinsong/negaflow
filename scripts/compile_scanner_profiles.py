#!/usr/bin/env python3
# /// script
# requires-python = ">=3.11"
# ///
# --- How to run ---------------------------------------------------------------
# python3 scripts/compile_scanner_profiles.py --source LUT_target/SOURCE --out LUT_target/PROFILES --resource-out Sources/Chromabase/ScannerProfiles

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import string
import tempfile
from dataclasses import dataclass
from pathlib import Path
from statistics import fmean
from typing import Final, TypeAlias

JsonScalar: TypeAlias = None | bool | int | float | str
JsonValue: TypeAlias = JsonScalar | list["JsonValue"] | dict[str, "JsonValue"]
JsonObject: TypeAlias = dict[str, JsonValue]

PROFILE_VERSION: Final[int] = 2
STAT_KEYS: Final[tuple[str, ...]] = (
    "p1", "p5", "p10", "p25", "p50", "p75", "p90", "p95", "p99",
    "clip_white_pct", "clip_black_pct", "contrast_p90_p10",
)
COLOR_KEYS: Final[tuple[str, ...]] = (
    "mean_r", "mean_g", "mean_b", "shadow_rg", "shadow_gb", "mid_rg", "mid_gb", "high_rg",
    "high_gb", "shadow_chroma", "mid_chroma", "high_chroma",
)
TEXTURE_KEYS: Final[tuple[str, ...]] = (
    "texture_luma_gradient_mean", "texture_sharpness_p95", "texture_sharpness_p99", "texture_grain_proxy_mean", "texture_grain_proxy_p90",
)
NEUTRAL_KEYS: Final[tuple[str, ...]] = ("neutral_a_median", "neutral_b_median")
MAX_CANDIDATES: Final[int] = 8
NEUTRAL_BIN_COUNT: Final[int] = 10
HUE_BIN_COUNT: Final[int] = 12
# 스캐너 간 hue 시그니처는 normalized source roll-label set이 일치하고
# REAL 이미지 수가 거의 같은 묶음만 비교한다. roll-label 일치는 촬영 원본
# 프레임 동일성을 증명하지 않으므로, 그 이상의 pairing 근거로 표현하지 않는다.
PAIRED_COUNT_TOLERANCE: Final[float] = 0.15
# hue bin 커버리지(%)가 양쪽 스캐너 모두 이 값 이상일 때만 그 bin 의 비교를 신뢰한다.
MIN_HUE_COVERAGE_PCT: Final[float] = 0.5
# Provenance matching is shared conceptually with
# ScannerTargetGrade.normalizedProvenanceComponent in Swift.  To keep Python,
# Swift, locale, and Unicode database versions from silently disagreeing, the
# compiler accepts ASCII provenance components only and defines normalization as:
# trim these six ASCII whitespace bytes, then map A-Z to a-z byte-for-byte.
PORTABLE_ASCII_WHITESPACE: Final[str] = " \t\r\n\v\f"
ASCII_LOWER_TRANSLATION: Final[dict[int, int]] = str.maketrans(
    string.ascii_uppercase,
    string.ascii_lowercase,
)


@dataclass(frozen=True, slots=True)
class RollProfile:
    path: Path
    scanner: str
    kind: str
    film_key: str
    image_count: int
    payload: JsonObject


@dataclass(frozen=True, slots=True)
class GroupSpec:
    scanner: str; kind: str; film_key: str; roll_count: int; image_count: int
    profiles: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class RollSpec:
    scanner: str
    kind: str
    film_key: str
    image_count: int
    profile_path: str


class ProfileCompileError(RuntimeError):
    pass


def reject_constant(value: str) -> None:
    raise ProfileCompileError(f"non-standard JSON constant: {value}")


def read_json(path: Path) -> JsonObject:
    data = json.loads(path.read_text(encoding="utf-8"), parse_constant=reject_constant)
    if not isinstance(data, dict):
        raise ProfileCompileError(f"expected JSON object: {path}")
    return data


def as_object(value: JsonValue, label: str) -> JsonObject:
    if isinstance(value, dict):
        return value
    raise ProfileCompileError(f"missing object: {label}")


def as_list(value: JsonValue, label: str) -> list[JsonValue]:
    if isinstance(value, list):
        return value
    raise ProfileCompileError(f"missing list: {label}")


def as_str(value: JsonValue, label: str) -> str:
    if isinstance(value, str):
        return value
    raise ProfileCompileError(f"missing string: {label}")


def nonempty_str(value: JsonValue, label: str) -> str:
    result = as_str(value, label)
    if not result.strip():
        raise ProfileCompileError(f"empty string: {label}")
    return result


def as_int(value: JsonValue, label: str) -> int:
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    raise ProfileCompileError(f"missing int: {label}")


def number(value: JsonValue) -> float | None:
    if isinstance(value, int | float) and not isinstance(value, bool):
        numeric = float(value)
        return numeric if math.isfinite(numeric) else None
    return None


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    pos = (len(ordered) - 1) * pct
    low = math.floor(pos)
    high = math.ceil(pos)
    if low == high:
        return ordered[low]
    weight = pos - low
    return ordered[low] * (1.0 - weight) + ordered[high] * weight


def stats(values: list[float]) -> JsonObject:
    finite = [value for value in values if math.isfinite(value)]
    if not finite:
        return {"count": 0, "mean": 0.0, "median": 0.0, "p10": 0.0, "p90": 0.0, "min": 0.0, "max": 0.0}
    return {"count": len(finite), "mean": fmean(finite), "median": percentile(finite, 0.5), "p10": percentile(finite, 0.1), "p90": percentile(finite, 0.9), "min": min(finite), "max": max(finite)}


def slug(value: str) -> str:
    lowered = value.strip().translate(ASCII_LOWER_TRANSLATION)
    return re.sub(r"[^a-z0-9]+", "-", lowered).strip("-")


def profile_id(scanner: str, kind: str, film_key: str) -> str:
    components = (slug(scanner), slug(kind), slug(film_key))
    if any(not component for component in components):
        raise ProfileCompileError(
            f"profile identity has an empty portable slug: {(scanner, kind, film_key)!r}"
        )
    return "__".join(components)


def normalized_provenance_component(value: str) -> str:
    if not value.isascii():
        raise ProfileCompileError(
            f"non-ASCII provenance component is not portable across Python/Swift: {value!r}"
        )
    return value.strip(PORTABLE_ASCII_WHITESPACE).translate(ASCII_LOWER_TRANSLATION)


def source_roll_label_set(group: GroupSpec) -> frozenset[str] | None:
    """Scanner/prefix가 제거된 normalized source roll-label set, 또는 불완전한 경우 None."""
    if group.roll_count <= 0 or len(group.profiles) != group.roll_count:
        return None
    scanner_key = normalized_provenance_component(group.scanner)
    labels: list[str] = []
    for source in group.profiles:
        components = [
            normalized_provenance_component(component)
            for component in source.replace("\\", "/").split("/")
            # Swift split(omittingEmptySubsequences: true) removes only truly
            # empty path segments before trimming; whitespace-only segments stay.
            if component
        ]
        try:
            scanner_index = components.index(scanner_key)
        except ValueError:
            return None
        if scanner_index + 2 >= len(components):
            return None
        labels.append("/".join(components[scanner_index + 1:]))
    unique = frozenset(labels)
    return unique if len(unique) == len(labels) else None


def rows_for(rolls: list[RollProfile]) -> list[JsonObject]:
    rows: list[JsonObject] = []
    for roll in rolls:
        for row in as_list(roll.payload.get("cut_summaries", []), f"{roll.path}: cut_summaries"):
            rows.append(as_object(row, f"{roll.path}: cut_summaries row"))
    return rows


def summarize_rows(rows: list[JsonObject], keys: tuple[str, ...]) -> JsonObject:
    result: JsonObject = {}
    for key in keys:
        result[key] = stats([value for row in rows if (value := number(row.get(key))) is not None])
    return result


def aggregate_scene_buckets(rolls: list[RollProfile]) -> list[JsonObject]:
    buckets: dict[tuple[str, str], list[JsonObject]] = {}
    candidates: dict[tuple[str, str], list[JsonObject]] = {}
    for roll in rolls:
        families = as_object(roll.payload.get("scene_buckets", {}), f"{roll.path}: scene_buckets")
        for family, raw_group in families.items():
            group = as_object(raw_group, f"{roll.path}: scene_buckets.{family}")
            for name, raw_bucket in group.items():
                bucket = as_object(raw_bucket, f"{roll.path}: scene_buckets.{family}.{name}")
                buckets.setdefault((family, name), []).append(bucket)
                for item in as_list(bucket.get("representative_candidates", []), "representative_candidates"):
                    candidates.setdefault((family, name), []).append(as_object(item, "representative candidate"))
    result: list[JsonObject] = []
    for (family, name), bucket_list in sorted(buckets.items()):
        summaries = [as_object(bucket.get("summary", {}), "bucket summary") for bucket in bucket_list]
        image_count = sum(as_int(bucket.get("image_count", 0), "bucket image_count") for bucket in bucket_list)
        result.append({
            "family": family,
            "name": name,
            "imageCount": image_count,
            "tone": summarize_bucket_stats(summaries, STAT_KEYS),
            "color": summarize_bucket_stats(summaries, COLOR_KEYS + NEUTRAL_KEYS),
            "texture": summarize_bucket_stats(summaries, TEXTURE_KEYS),
            "representativeCandidates": trim_candidates(candidates.get((family, name), [])),
        })
    return result


def summarize_bucket_stats(summaries: list[JsonObject], keys: tuple[str, ...]) -> JsonObject:
    result: JsonObject = {}
    for key in keys:
        values: list[float] = []
        for summary in summaries:
            stat = as_object(summary.get(key, {}), f"summary.{key}")
            value = number(stat.get("median"))
            if value is not None:
                values.append(value)
        result[key] = stats(values)
    return result


def trim_candidates(rows: list[JsonObject]) -> list[JsonObject]:
    seen: set[str] = set()
    result: list[JsonObject] = []
    for row in rows:
        stem = as_str(row.get("stem", ""), "candidate.stem")
        if stem in seen:
            continue
        seen.add(stem)
        result.append({
            "stem": stem,
            "realFile": as_str(row.get("real_file", ""), "candidate.real_file"),
            "p50": number(row.get("p50")) or 0.0,
            "contrastP90P10": number(row.get("contrast_p90_p10")) or 0.0,
            "midChroma": number(row.get("mid_chroma")) or 0.0,
        })
        if len(result) >= MAX_CANDIDATES:
            break
    return result


def aggregate_coverage(rolls: list[RollProfile]) -> list[JsonObject]:
    grouped: dict[str, list[JsonObject]] = {}
    for roll in rolls:
        raw = as_object(roll.payload.get("coverage_candidates", {}), f"{roll.path}: coverage_candidates")
        for axis, values in raw.items():
            for item in as_list(values, f"coverage {axis}"):
                grouped.setdefault(axis, []).append(as_object(item, f"coverage {axis} row"))
    return [{"axis": axis, "candidates": trim_candidates(rows)} for axis, rows in sorted(grouped.items())]


def roll_stat_median(roll: RollProfile, container: JsonValue, key: str) -> float | None:
    """Median of a per-roll Stat block ({count, mean, median, ...}); None if empty."""
    obj = as_object(container, f"{roll.path}: stat container")
    stat = obj.get(key)
    if not isinstance(stat, dict):
        return None
    count = number(stat.get("count"))
    if count is None or count < 1.0:
        return None
    return number(stat.get("median"))


def weighted_bin_median(rolls: list[RollProfile], list_key: str, index: int, stat_key: str) -> float | None:
    """Image-count-weighted mean of per-roll bin medians (rolls with empty bins skipped)."""
    total_weight = 0.0
    total = 0.0
    for roll in rolls:
        bins = as_list(roll.payload.get(list_key, []), f"{roll.path}: {list_key}")
        if index >= len(bins):
            continue
        value = roll_stat_median(roll, bins[index], stat_key)
        if value is None:
            continue
        weight = float(roll.image_count)
        total += value * weight
        total_weight += weight
    if total_weight <= 0.0:
        return None
    return total / total_weight


def aggregate_neutral_bins(rolls: list[RollProfile]) -> list[JsonObject]:
    """중립축(HSV sat<0.08 픽셀) luma bin 별 Lab a*/b* 드리프트 — 스캐너의 중립 렌더링 시그니처."""
    bins: list[JsonObject] = []
    for index in range(NEUTRAL_BIN_COUNT):
        lab_a = weighted_bin_median(rolls, "neutral_axis", index, "lab_a_median")
        lab_b = weighted_bin_median(rolls, "neutral_axis", index, "lab_b_median")
        coverage = weighted_bin_median(rolls, "neutral_axis", index, "coverage_pct") or 0.0
        if lab_a is None or lab_b is None:
            continue
        bins.append({
            "lumaCenter": (index + 0.5) / NEUTRAL_BIN_COUNT,
            "coveragePct": coverage,
            "labA": lab_a,
            "labB": lab_b,
        })
    return bins


@dataclass(frozen=True, slots=True)
class HueBinAggregate:
    coverage: float
    saturation: float
    lab_a: float
    lab_b: float


def aggregate_hue_bins(rolls: list[RollProfile]) -> list[HueBinAggregate | None]:
    result: list[HueBinAggregate | None] = []
    for index in range(HUE_BIN_COUNT):
        coverage = weighted_bin_median(rolls, "hue_bins", index, "coverage_pct")
        saturation = weighted_bin_median(rolls, "hue_bins", index, "saturation_median")
        lab_a = weighted_bin_median(rolls, "hue_bins", index, "lab_a_median")
        lab_b = weighted_bin_median(rolls, "hue_bins", index, "lab_b_median")
        if coverage is None or saturation is None or lab_a is None or lab_b is None:
            result.append(None)
            continue
        result.append(HueBinAggregate(coverage, saturation, lab_a, lab_b))
    return result


def wrap_degrees(value: float) -> float:
    return (value + 180.0) % 360.0 - 180.0


def compute_hue_responses(
    groups: list[tuple[GroupSpec, list[HueBinAggregate | None]]],
) -> dict[tuple[str, str], list[JsonObject]]:
    """스캐너 간(hue bin 별) 채도 비율/Lab hue 회전 시그니처.

    같은 kind + film_key에서 normalized source roll-label set이 정확히 일치하고
    이미지 수가 ±15% 이내일 때만 그 필름을 비교에 포함한다. 이것은 roll-label
    matched 근거이며, 촬영 원본 프레임 동일성이나 순수 장치 차이를 증명하지 않는다.
    비율은 두 스캐너의 기하평균을 중심으로 대칭 분배하고, bin 간 기하평균이 1이 되도록
    정규화한다(전역 채도 베이스라인은 별도, 여기는 hue 상대 변조만).
    """
    by_kind: dict[str, dict[str, dict[str, tuple[GroupSpec, list[HueBinAggregate | None]]]]] = {}
    for spec, bins in groups:
        by_kind.setdefault(spec.kind, {}).setdefault(spec.film_key, {})[spec.scanner] = (spec, bins)

    responses: dict[tuple[str, str], list[JsonObject]] = {}
    for kind, films in sorted(by_kind.items()):
        scanners = sorted({scanner for film in films.values() for scanner in film})
        if len(scanners) != 2:
            continue
        first, second = scanners[0], scanners[1]
        # bin 별 누적: (weight, ln(sat_first/sat_second), hue delta, anchor 벡터)
        acc: list[list[float]] = [[0.0, 0.0, 0.0, 0.0, 0.0] for _ in range(HUE_BIN_COUNT)]
        for film_key, per_scanner in sorted(films.items()):
            if first not in per_scanner or second not in per_scanner:
                continue
            spec_a, bins_a = per_scanner[first]
            spec_b, bins_b = per_scanner[second]
            rolls_a = source_roll_label_set(spec_a)
            rolls_b = source_roll_label_set(spec_b)
            if rolls_a is None or rolls_b is None or rolls_a != rolls_b:
                continue
            count_a, count_b = spec_a.image_count, spec_b.image_count
            if min(count_a, count_b) == 0:
                continue
            if abs(count_a - count_b) / max(count_a, count_b) > PAIRED_COUNT_TOLERANCE:
                continue
            for index in range(HUE_BIN_COUNT):
                bin_a, bin_b = bins_a[index], bins_b[index]
                if bin_a is None or bin_b is None:
                    continue
                if min(bin_a.coverage, bin_b.coverage) < MIN_HUE_COVERAGE_PCT:
                    continue
                if bin_a.saturation <= 1e-6 or bin_b.saturation <= 1e-6:
                    continue
                hue_a = math.degrees(math.atan2(bin_a.lab_b, bin_a.lab_a))
                hue_b = math.degrees(math.atan2(bin_b.lab_b, bin_b.lab_a))
                weight = min(bin_a.coverage, bin_b.coverage)
                acc[index][0] += weight
                acc[index][1] += weight * math.log(bin_a.saturation / bin_b.saturation)
                acc[index][2] += weight * wrap_degrees(hue_a - hue_b)
                anchor = math.radians((hue_a + wrap_degrees(hue_b - hue_a) / 2.0))
                acc[index][3] += weight * math.cos(anchor)
                acc[index][4] += weight * math.sin(anchor)

        rows: list[JsonObject] = []
        for index in range(HUE_BIN_COUNT):
            weight, ln_sum, hue_sum, ax, ay = acc[index]
            if weight <= 0.0:
                continue
            rows.append({
                "weight": weight,
                "lnRatio": ln_sum / weight,
                "hueDelta": hue_sum / weight,
                "labHueDegrees": math.degrees(math.atan2(ay, ax)) % 360.0,
            })
        if not rows:
            continue
        # bin 간 가중 기하평균 → 1 정규화(전역 채도와 분리).
        total_weight = sum(as_float(row["weight"]) for row in rows)
        mean_ln = sum(as_float(row["lnRatio"]) * as_float(row["weight"]) for row in rows) / total_weight
        for scanner, sign in ((first, 0.5), (second, -0.5)):
            response = [
                {
                    "labHueDegrees": round(as_float(row["labHueDegrees"]), 3),
                    "chromaGain": round(math.exp((as_float(row["lnRatio"]) - mean_ln) * sign), 5),
                    "hueRotateDegrees": round(as_float(row["hueDelta"]) * sign, 3),
                    "weight": round(as_float(row["weight"]), 3),
                }
                for row in rows
            ]
            responses[(scanner, kind)] = sorted(response, key=lambda item: as_float(item["labHueDegrees"]))
    return responses


def as_float(value: JsonValue) -> float:
    numeric = number(value)
    if numeric is None:
        raise ProfileCompileError(f"expected number: {value!r}")
    return numeric


def build_profile(
    group: GroupSpec,
    rolls: list[RollProfile],
    hue_response: list[JsonObject] | None,
) -> JsonObject:
    rows = rows_for(rolls)
    if not rows:
        raise ProfileCompileError(f"empty cut_summaries for {group.scanner}/{group.kind}/{group.film_key}")
    payload: JsonObject = {
        "schemaVersion": PROFILE_VERSION, "id": profile_id(group.scanner, group.kind, group.film_key),
        "displayName": f"{group.scanner} {group.kind} {group.film_key}",
        "scanner": group.scanner,
        "kind": group.kind,
        "filmKey": group.film_key,
        "validationStatus": "realOnly",
        "rollCount": group.roll_count,
        "imageCount": group.image_count,
        "singleRollLimited": group.roll_count < 2,
        "sourceProfiles": list(group.profiles),
        "tone": summarize_rows(rows, STAT_KEYS),
        "color": summarize_rows(rows, COLOR_KEYS),
        "neutralAxis": summarize_rows(rows, NEUTRAL_KEYS),
        "neutralAxisBins": aggregate_neutral_bins(rolls),
        "texture": summarize_rows(rows, TEXTURE_KEYS),
        "sceneBuckets": aggregate_scene_buckets(rolls),
        "coverageCandidates": aggregate_coverage(rolls),
    }
    if hue_response:
        payload["hueResponse"] = hue_response
    digest = hashlib.sha256(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    payload["profileHash"] = f"sha256:{digest}"
    return payload


def parse_group(raw: JsonValue) -> GroupSpec:
    group = as_object(raw, "film_index group")
    return GroupSpec(
        scanner=nonempty_str(group.get("scanner"), "group.scanner"),
        kind=nonempty_str(group.get("kind"), "group.kind"),
        film_key=nonempty_str(group.get("film_key"), "group.film_key"),
        roll_count=as_int(group.get("roll_count"), "group.roll_count"),
        image_count=as_int(group.get("image_count"), "group.image_count"),
        profiles=tuple(nonempty_str(item, "group.profiles[]") for item in as_list(group.get("profiles"), "group.profiles")),
    )


def parse_roll_spec(raw: JsonValue) -> RollSpec:
    row = as_object(raw, "film_index profile")
    return RollSpec(
        scanner=nonempty_str(row.get("scanner"), "profile.scanner"),
        kind=nonempty_str(row.get("kind"), "profile.kind"),
        film_key=nonempty_str(row.get("film_key"), "profile.film_key"),
        image_count=as_int(row.get("image_count"), "profile.image_count"),
        profile_path=nonempty_str(row.get("profile_path"), "profile.profile_path"),
    )


def resolve_source_profile(source: Path, raw_path: str, label: str) -> tuple[str, Path]:
    declared = Path(raw_path.replace("\\", "/"))
    if declared.is_absolute() or ".." in declared.parts:
        raise ProfileCompileError(f"unsafe source profile path: {label}: {raw_path!r}")
    source_root = source.resolve()
    path = (source.parent / declared).resolve()
    try:
        key = path.relative_to(source_root).as_posix()
    except ValueError as error:
        raise ProfileCompileError(
            f"source profile path escapes source directory: {label}: {raw_path!r}"
        ) from error
    return key, path


def load_roll(source: Path, profile_path: str, declaration: RollSpec) -> RollProfile:
    _, path = resolve_source_profile(source, profile_path, "group.profiles[]")
    payload = read_json(path)
    meta = as_object(payload.get("profile_metadata"), f"{path}: profile_metadata")
    roll = RollProfile(
        path=path,
        scanner=nonempty_str(meta.get("scanner"), "metadata.scanner"),
        kind=nonempty_str(meta.get("kind"), "metadata.kind"),
        film_key=nonempty_str(meta.get("film_key"), "metadata.film_key"),
        image_count=as_int(payload.get("image_count"), "profile.image_count"),
        payload=payload,
    )
    expected = (declaration.scanner, declaration.kind, declaration.film_key)
    actual = (roll.scanner, roll.kind, roll.film_key)
    if actual != expected:
        raise ProfileCompileError(
            f"roll metadata does not match film_index for {path}: expected {expected!r}, got {actual!r}"
        )
    if roll.image_count != declaration.image_count:
        raise ProfileCompileError(
            f"roll image_count does not match film_index for {path}: "
            f"expected {declaration.image_count}, got {roll.image_count}"
        )
    if roll.image_count <= 0:
        raise ProfileCompileError(f"roll image_count must be positive: {path}")
    cut_summaries = as_list(payload.get("cut_summaries"), f"{path}: cut_summaries")
    if len(cut_summaries) != roll.image_count:
        raise ProfileCompileError(
            f"roll image_count does not match actual cut_summaries for {path}: "
            f"declared {roll.image_count}, actual {len(cut_summaries)}"
        )
    for index, row in enumerate(cut_summaries):
        as_object(row, f"{path}: cut_summaries[{index}]")
    return roll


def load_and_validate_index(
    source: Path,
    index: JsonObject,
) -> list[tuple[GroupSpec, list[RollProfile]]]:
    raw_rolls = as_list(index.get("profiles"), "film_index.profiles")
    declared_profile_count = as_int(index.get("profile_count"), "film_index.profile_count")
    if declared_profile_count <= 0 or declared_profile_count != len(raw_rolls):
        raise ProfileCompileError(
            "film_index.profile_count does not match film_index.profiles: "
            f"declared {declared_profile_count}, actual {len(raw_rolls)}"
        )

    declarations: dict[str, RollSpec] = {}
    for raw_roll in raw_rolls:
        declaration = parse_roll_spec(raw_roll)
        if declaration.image_count <= 0:
            raise ProfileCompileError(
                f"film_index profile image_count must be positive: {declaration.profile_path}"
            )
        key, _ = resolve_source_profile(
            source,
            declaration.profile_path,
            "film_index.profiles[].profile_path",
        )
        if key in declarations:
            raise ProfileCompileError(f"duplicate film_index profile_path: {key!r}")
        declarations[key] = declaration

    source_root = source.resolve()
    actual_paths: set[str] = set()
    for path in source.rglob("profile.json"):
        try:
            key = path.resolve().relative_to(source_root).as_posix()
        except ValueError as error:
            raise ProfileCompileError(f"source profile escapes source directory: {path}") from error
        actual_paths.add(key)
    declared_paths = set(declarations)
    if actual_paths != declared_paths:
        raise ProfileCompileError(
            "film_index/source profile path mismatch: "
            f"missing={sorted(declared_paths - actual_paths)}, "
            f"unlisted={sorted(actual_paths - declared_paths)}"
        )

    loaded: list[tuple[GroupSpec, list[RollProfile]]] = []
    group_keys: set[tuple[str, str, str]] = set()
    grouped_paths: set[str] = set()
    for raw_group in as_list(index.get("groups"), "film_index.groups"):
        group = parse_group(raw_group)
        group_key = (group.scanner, group.kind, group.film_key)
        if group_key in group_keys:
            raise ProfileCompileError(f"duplicate film_index group: {group_key!r}")
        group_keys.add(group_key)
        if group.roll_count <= 0 or group.roll_count != len(group.profiles):
            raise ProfileCompileError(
                f"group.roll_count mismatch for {group_key!r}: "
                f"declared {group.roll_count}, actual {len(group.profiles)}"
            )
        if group.image_count <= 0:
            raise ProfileCompileError(f"group.image_count must be positive: {group_key!r}")
        if source_roll_label_set(group) is None:
            raise ProfileCompileError(
                f"group source provenance is incomplete, duplicated, or not portable: {group_key!r}"
            )

        rolls: list[RollProfile] = []
        group_paths: set[str] = set()
        for raw_path in group.profiles:
            key, _ = resolve_source_profile(source, raw_path, "film_index.groups[].profiles[]")
            if key in group_paths:
                raise ProfileCompileError(f"duplicate profile in group {group_key!r}: {key!r}")
            group_paths.add(key)
            if key in grouped_paths:
                raise ProfileCompileError(f"profile appears in multiple groups: {key!r}")
            declaration = declarations.get(key)
            if declaration is None:
                raise ProfileCompileError(f"group references undeclared profile: {key!r}")
            declared_group_key = (
                declaration.scanner,
                declaration.kind,
                declaration.film_key,
            )
            if declared_group_key != group_key:
                raise ProfileCompileError(
                    f"group identity does not match profile declaration for {key}: "
                    f"expected {declared_group_key!r}, got {group_key!r}"
                )
            roll = load_roll(source, raw_path, declaration)
            if (roll.scanner, roll.kind, roll.film_key) != group_key:
                raise ProfileCompileError(
                    f"group identity does not match roll metadata for {key}: {group_key!r}"
                )
            rolls.append(roll)
            grouped_paths.add(key)
        actual_image_count = sum(roll.image_count for roll in rolls)
        if group.image_count != actual_image_count:
            raise ProfileCompileError(
                f"group.image_count mismatch for {group_key!r}: "
                f"declared {group.image_count}, actual {actual_image_count}"
            )
        loaded.append((group, rolls))

    if grouped_paths != declared_paths:
        raise ProfileCompileError(
            "every declared profile must appear in exactly one group: "
            f"missing={sorted(declared_paths - grouped_paths)}"
        )
    return loaded


def write_json(path: Path, payload: JsonObject) -> str:
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")
    replace_file_bytes(path, encoded)
    return f"sha256:{hashlib.sha256(encoded).hexdigest()}"


def write_manifest_json(path: Path, payload: JsonObject) -> str:
    """Serialize manifest bytes in the bundle's stable, explicitly ordered layout."""
    encoded = (
        json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=False, allow_nan=False)
        + "\n"
    ).encode("utf-8")
    replace_file_bytes(path, encoded)
    return f"sha256:{hashlib.sha256(encoded).hexdigest()}"


def replace_file_bytes(path: Path, encoded: bytes) -> None:
    """Atomically replace an output entry without following links at its final path."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
    )
    temporary_path = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(encoded)
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def remove_stale_json_outputs(directory: Path, expected_names: set[str]) -> None:
    if not directory.exists():
        return
    stale: list[Path] = []
    invalid: list[Path] = []
    for path in sorted(directory.rglob("*.json")):
        is_expected_direct_file = path.parent == directory and path.name in expected_names
        if is_expected_direct_file and path.is_file() and not path.is_symlink():
            continue
        if path.is_file() or path.is_symlink():
            # Symlinks are always replaced rather than followed, including when
            # their names match an expected output file.
            stale.append(path)
        else:
            invalid.append(path)
    if invalid:
        raise ProfileCompileError(
            f"refusing to remove non-file stale JSON outputs: {[str(path) for path in invalid]}"
        )
    for path in stale:
        path.unlink()


def compile_profiles(source: Path, out_dir: Path, resource_out: Path | None) -> JsonObject:
    index = read_json(source / "film_index.json")
    loaded = load_and_validate_index(source, index)
    identities: dict[str, tuple[str, str, str]] = {}
    for group, _ in loaded:
        identity = (group.scanner, group.kind, group.film_key)
        identifier = profile_id(*identity)
        if previous := identities.get(identifier):
            raise ProfileCompileError(
                f"lossy profile id collision for {identifier!r}: {previous!r} and {identity!r}"
            )
        identities[identifier] = identity
    hue_responses = compute_hue_responses(
        [(group, aggregate_hue_bins(rolls)) for group, rolls in loaded]
    )
    profiles = [
        build_profile(group, rolls, hue_responses.get((group.scanner, group.kind)))
        for group, rolls in loaded
    ]
    expected_names = {
        f"{as_str(profile['id'], 'profile.id')}.json"
        for profile in profiles
    } | {"manifest.json"}
    remove_stale_json_outputs(out_dir, expected_names)
    if resource_out is not None:
        remove_stale_json_outputs(resource_out, expected_names)

    manifest_profiles: list[JsonObject] = []
    for profile in profiles:
        profile_identifier = as_str(profile["id"], "profile.id")
        file_hash = write_json(out_dir / f"{profile_identifier}.json", profile)
        if resource_out is not None:
            resource_hash = write_json(resource_out / f"{profile_identifier}.json", profile)
            if resource_hash != file_hash:
                raise ProfileCompileError(f"non-deterministic profile serialization: {profile_identifier}")
        manifest_profiles.append({
            "id": profile_identifier,
            "profileHash": as_str(profile["profileHash"], "profile.profileHash"),
            "fileSHA256": file_hash,
        })
    # Key order is explicit because ScannerProfileBundleIdentity hashes the raw
    # manifest bytes.  Do not rely on a JSON encoder's recursive sort policy.
    manifest: JsonObject = {
        "profileCount": len(profiles),
        "profiles": manifest_profiles,
        "schemaVersion": PROFILE_VERSION,
    }
    write_manifest_json(out_dir / "manifest.json", manifest)
    if resource_out is not None:
        write_manifest_json(resource_out / "manifest.json", manifest)
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Compile Negaflow scanner aggregate profiles.")
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--resource-out", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest = compile_profiles(args.source, args.out, args.resource_out)
    print(json.dumps(manifest, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
