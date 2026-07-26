#!/usr/bin/env python3
"""Evaluate a versioned negaflow profile corpus against an accepted baseline.

The evaluator consumes the paired ``summary.json`` written by
``LUT_target/analyze_lut_target.py``.  It does not create quality thresholds:
every compared metric, its direction, and its allowed absolute regression must
be declared in the corpus manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Final, TypeAlias

JsonScalar: TypeAlias = None | bool | int | float | str
JsonValue: TypeAlias = JsonScalar | list["JsonValue"] | dict[str, "JsonValue"]
JsonObject: TypeAlias = dict[str, JsonValue]

MANIFEST_SCHEMA_VERSION: Final[int] = 1
REPORT_SCHEMA_VERSION: Final[int] = 1
ROLES: Final[frozenset[str]] = frozenset({"calibration", "holdout"})
DIRECTIONS: Final[frozenset[str]] = frozenset({
    "lowerIsBetter",
    "higherIsBetter",
    "absoluteLowerIsBetter",
})
HASH_PATTERN: Final[re.Pattern[str]] = re.compile(r"^sha256:[0-9a-f]{64}$")
MANIFEST_KEYS: Final[frozenset[str]] = frozenset({
    "schemaVersion",
    "corpusVersion",
    "acceptedBaselineSHA256",
    "cases",
    "metrics",
})
CASE_KEYS: Final[frozenset[str]] = frozenset({"role", "stem", "real", "target"})
FILE_KEYS: Final[frozenset[str]] = frozenset({"path", "sha256"})
METRIC_KEYS: Final[frozenset[str]] = frozenset({
    "name",
    "direction",
    "allowedRegression",
})
SUMMARY_LIST_KEYS: Final[tuple[str, ...]] = (
    "missing_target",
    "missing_real",
    "duplicate_real_stems",
    "duplicate_target_stems",
    "failed_pairs",
)
HASH_CHUNK_SIZE: Final[int] = 1024 * 1024


class GateInputError(RuntimeError):
    """Raised when gate inputs are incomplete, malformed, or untrusted."""


@dataclass(frozen=True, slots=True)
class CorpusFile:
    path: str
    sha256: str


@dataclass(frozen=True, slots=True)
class CorpusCase:
    role: str
    stem: str
    real: CorpusFile
    target: CorpusFile


@dataclass(frozen=True, slots=True)
class MetricRule:
    name: str
    direction: str
    allowed_regression: float


@dataclass(frozen=True, slots=True)
class CorpusManifest:
    corpus_version: str
    accepted_baseline_sha256: str
    cases: tuple[CorpusCase, ...]
    metrics: tuple[MetricRule, ...]


def reject_json_constant(value: str) -> None:
    raise GateInputError(f"non-standard JSON constant: {value}")


def finite_walk(value: JsonValue) -> bool:
    if isinstance(value, float):
        return math.isfinite(value)
    if isinstance(value, list):
        return all(finite_walk(item) for item in value)
    if isinstance(value, dict):
        return all(finite_walk(item) for item in value.values())
    return True


def read_json(path: Path, label: str) -> JsonObject:
    value, _ = read_json_with_hash(path, label)
    return value


def read_bytes_with_hash(path: Path, label: str) -> tuple[bytes, str]:
    try:
        raw_bytes = path.read_bytes()
    except OSError as error:
        raise GateInputError(f"{label}: cannot read {path}: {error}") from error
    digest = hashlib.sha256(raw_bytes).hexdigest()
    return raw_bytes, f"sha256:{digest}"


def parse_json_bytes(raw_bytes: bytes, label: str) -> JsonObject:
    try:
        raw = raw_bytes.decode("utf-8")
    except UnicodeError as error:
        raise GateInputError(f"{label}: invalid UTF-8: {error}") from error
    try:
        value = json.loads(raw, parse_constant=reject_json_constant)
    except json.JSONDecodeError as error:
        raise GateInputError(f"{label}: invalid JSON: {error}") from error
    if not isinstance(value, dict):
        raise GateInputError(f"{label}: expected object")
    if not finite_walk(value):
        raise GateInputError(f"{label}: contains non-finite number")
    return value


def read_json_with_hash(path: Path, label: str) -> tuple[JsonObject, str]:
    raw_bytes, digest = read_bytes_with_hash(path, label)
    return parse_json_bytes(raw_bytes, label), digest


def require_exact_keys(value: JsonObject, keys: frozenset[str], label: str) -> None:
    actual = frozenset(value)
    missing = sorted(keys - actual)
    unknown = sorted(actual - keys)
    if missing:
        raise GateInputError(f"{label}: missing keys: {', '.join(missing)}")
    if unknown:
        raise GateInputError(f"{label}: unknown keys: {', '.join(unknown)}")


def as_object(value: JsonValue, label: str) -> JsonObject:
    if not isinstance(value, dict):
        raise GateInputError(f"{label}: expected object")
    return value


def as_list(value: JsonValue, label: str) -> list[JsonValue]:
    if not isinstance(value, list):
        raise GateInputError(f"{label}: expected list")
    return value


def as_nonempty_string(value: JsonValue, label: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise GateInputError(f"{label}: expected non-empty string")
    return value


def as_integer(value: JsonValue, label: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool):
        raise GateInputError(f"{label}: expected integer")
    return value


def as_finite_number(value: JsonValue, label: str) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise GateInputError(f"{label}: expected finite number")
    result = float(value)
    if not math.isfinite(result):
        raise GateInputError(f"{label}: expected finite number")
    return result


def parse_corpus_file(value: JsonValue, label: str) -> CorpusFile:
    payload = as_object(value, label)
    require_exact_keys(payload, FILE_KEYS, label)
    path = as_nonempty_string(payload.get("path"), f"{label}.path")
    sha256 = as_nonempty_string(payload.get("sha256"), f"{label}.sha256")
    if HASH_PATTERN.fullmatch(sha256) is None:
        raise GateInputError(f"{label}.sha256: expected sha256:<64 lowercase hex>")
    return CorpusFile(path=path, sha256=sha256)


def parse_manifest(path: Path) -> CorpusManifest:
    payload = read_json(path, "manifest")
    require_exact_keys(payload, MANIFEST_KEYS, "manifest")
    schema_version = as_integer(payload.get("schemaVersion"), "manifest.schemaVersion")
    if schema_version != MANIFEST_SCHEMA_VERSION:
        raise GateInputError(
            "manifest.schemaVersion: "
            f"expected {MANIFEST_SCHEMA_VERSION}, got {schema_version}"
        )
    corpus_version = as_nonempty_string(
        payload.get("corpusVersion"), "manifest.corpusVersion"
    )
    accepted_baseline_sha256 = as_nonempty_string(
        payload.get("acceptedBaselineSHA256"),
        "manifest.acceptedBaselineSHA256",
    )
    if HASH_PATTERN.fullmatch(accepted_baseline_sha256) is None:
        raise GateInputError(
            "manifest.acceptedBaselineSHA256: expected sha256:<64 lowercase hex>"
        )

    raw_cases = as_list(payload.get("cases"), "manifest.cases")
    if not raw_cases:
        raise GateInputError("manifest.cases: corpus must not be empty")
    cases: list[CorpusCase] = []
    seen_stems: set[str] = set()
    for index, raw_case in enumerate(raw_cases):
        label = f"manifest.cases[{index}]"
        case = as_object(raw_case, label)
        require_exact_keys(case, CASE_KEYS, label)
        role = as_nonempty_string(case.get("role"), f"{label}.role")
        if role not in ROLES:
            raise GateInputError(
                f"{label}.role: expected one of {', '.join(sorted(ROLES))}"
            )
        stem = as_nonempty_string(case.get("stem"), f"{label}.stem")
        if stem in seen_stems:
            raise GateInputError(f"manifest.cases: duplicate stem {stem!r}")
        seen_stems.add(stem)
        cases.append(CorpusCase(
            role=role,
            stem=stem,
            real=parse_corpus_file(case.get("real"), f"{label}.real"),
            target=parse_corpus_file(case.get("target"), f"{label}.target"),
        ))
    if not any(case.role == "calibration" for case in cases):
        raise GateInputError("manifest.cases: at least one calibration case is required")
    if not any(case.role == "holdout" for case in cases):
        raise GateInputError("manifest.cases: at least one holdout case is required")

    raw_metrics = as_list(payload.get("metrics"), "manifest.metrics")
    if not raw_metrics:
        raise GateInputError("manifest.metrics: metric rules must not be empty")
    metrics: list[MetricRule] = []
    seen_metrics: set[str] = set()
    for index, raw_metric in enumerate(raw_metrics):
        label = f"manifest.metrics[{index}]"
        metric = as_object(raw_metric, label)
        require_exact_keys(metric, METRIC_KEYS, label)
        name = as_nonempty_string(metric.get("name"), f"{label}.name")
        if name in seen_metrics:
            raise GateInputError(f"manifest.metrics: duplicate metric {name!r}")
        seen_metrics.add(name)
        direction = as_nonempty_string(metric.get("direction"), f"{label}.direction")
        if direction not in DIRECTIONS:
            raise GateInputError(
                f"{label}.direction: expected one of {', '.join(sorted(DIRECTIONS))}"
            )
        allowed = as_finite_number(
            metric.get("allowedRegression"), f"{label}.allowedRegression"
        )
        if allowed < 0:
            raise GateInputError(f"{label}.allowedRegression: expected non-negative number")
        metrics.append(MetricRule(
            name=name,
            direction=direction,
            allowed_regression=allowed,
        ))
    return CorpusManifest(
        corpus_version,
        accepted_baseline_sha256,
        tuple(cases),
        tuple(metrics),
    )


def validate_string_list(value: JsonValue, label: str) -> list[str]:
    rows = as_list(value, label)
    result: list[str] = []
    for index, row in enumerate(rows):
        result.append(as_nonempty_string(row, f"{label}[{index}]"))
    return result


def parse_summary_payload(summary: JsonObject, label: str) -> dict[str, JsonObject]:
    if summary.get("mode") != "paired":
        raise GateInputError(f"{label}.mode: expected 'paired'")
    for key in SUMMARY_LIST_KEYS:
        entries = validate_string_list(summary.get(key), f"{label}.{key}")
        if entries:
            raise GateInputError(
                f"{label}.{key}: incomplete or ambiguous pairs: {', '.join(entries)}"
            )
    analyzed = as_list(summary.get("analyzed"), f"{label}.analyzed")
    if not analyzed:
        raise GateInputError(f"{label}.analyzed: expected at least one analyzed pair")
    by_stem: dict[str, JsonObject] = {}
    for index, raw_row in enumerate(analyzed):
        row_label = f"{label}.analyzed[{index}]"
        row = as_object(raw_row, row_label)
        stem = as_nonempty_string(row.get("stem"), f"{row_label}.stem")
        if stem in by_stem:
            raise GateInputError(f"{label}.analyzed: duplicate stem {stem!r}")
        by_stem[stem] = row
    return by_stem


def parse_summary(path: Path, label: str) -> dict[str, JsonObject]:
    return parse_summary_payload(read_json(path, label), label)


def validate_summary_corpus(
    rows: dict[str, JsonObject], manifest: CorpusManifest, label: str
) -> None:
    expected = {case.stem for case in manifest.cases}
    actual = set(rows)
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    if missing:
        raise GateInputError(f"{label}.analyzed: missing corpus stems: {', '.join(missing)}")
    if extra:
        raise GateInputError(f"{label}.analyzed: undeclared corpus stems: {', '.join(extra)}")


def resolve_data_file(data_root: Path, raw_path: str, label: str) -> Path:
    relative = Path(raw_path)
    if relative.is_absolute():
        raise GateInputError(f"{label}: expected path relative to data root")
    root = data_root.resolve()
    resolved = (root / relative).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as error:
        raise GateInputError(f"{label}: path escapes data root") from error
    if not resolved.is_file():
        raise GateInputError(f"{label}: file does not exist: {resolved}")
    return resolved


def resolve_summary_file(data_root: Path, raw_path: JsonValue, label: str) -> Path:
    path_string = as_nonempty_string(raw_path, label)
    path = Path(path_string)
    if path.is_absolute():
        resolved = path.resolve()
        if not resolved.is_file():
            raise GateInputError(f"{label}: file does not exist: {resolved}")
        return resolved
    return resolve_data_file(data_root, path_string, label)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            while chunk := handle.read(HASH_CHUNK_SIZE):
                digest.update(chunk)
    except OSError as error:
        raise GateInputError(f"cannot hash {path}: {error}") from error
    return f"sha256:{digest.hexdigest()}"


def verify_case_files(
    case: CorpusCase,
    candidate_row: JsonObject,
    data_root: Path,
) -> list[JsonObject]:
    results: list[JsonObject] = []
    for kind, expected in (("real", case.real), ("target", case.target)):
        label = f"case[{case.stem!r}].{kind}"
        manifest_path = resolve_data_file(data_root, expected.path, f"{label}.path")
        summary_key = f"{kind}_file"
        summary_path = resolve_summary_file(
            data_root, candidate_row.get(summary_key), f"candidate.{case.stem}.{summary_key}"
        )
        if summary_path != manifest_path:
            raise GateInputError(
                f"{label}: candidate summary path does not match manifest path"
            )
        actual_hash = sha256_file(manifest_path)
        if actual_hash != expected.sha256:
            raise GateInputError(
                f"{label}.sha256: expected {expected.sha256}, got {actual_hash}"
            )
        results.append({
            "stem": case.stem,
            "role": case.role,
            "kind": kind,
            "path": expected.path,
            "sha256": actual_hash,
            "passed": True,
        })
    return results


def metric_regression(candidate: float, baseline: float, direction: str) -> float:
    if direction == "lowerIsBetter":
        return candidate - baseline
    if direction == "higherIsBetter":
        return baseline - candidate
    if direction == "absoluteLowerIsBetter":
        return abs(candidate) - abs(baseline)
    raise AssertionError(f"unvalidated metric direction: {direction}")


def metric_passed(
    candidate: float, baseline: float, direction: str, allowed: float
) -> bool:
    if direction == "lowerIsBetter":
        return candidate <= baseline + allowed
    if direction == "higherIsBetter":
        return candidate + allowed >= baseline
    if direction == "absoluteLowerIsBetter":
        return abs(candidate) <= abs(baseline) + allowed
    raise AssertionError(f"unvalidated metric direction: {direction}")


def compare_holdout(
    manifest: CorpusManifest,
    candidate_rows: dict[str, JsonObject],
    baseline_rows: dict[str, JsonObject],
) -> list[JsonObject]:
    comparisons: list[JsonObject] = []
    for case in manifest.cases:
        if case.role != "holdout":
            continue
        candidate_row = candidate_rows[case.stem]
        baseline_row = baseline_rows[case.stem]
        for metric in manifest.metrics:
            candidate = as_finite_number(
                candidate_row.get(metric.name),
                f"candidate.{case.stem}.{metric.name}",
            )
            baseline = as_finite_number(
                baseline_row.get(metric.name),
                f"baseline.{case.stem}.{metric.name}",
            )
            passed = metric_passed(
                candidate, baseline, metric.direction, metric.allowed_regression
            )
            comparisons.append({
                "stem": case.stem,
                "metric": metric.name,
                "direction": metric.direction,
                "allowedRegression": metric.allowed_regression,
                "baseline": baseline,
                "candidate": candidate,
                "signedRegression": metric_regression(
                    candidate, baseline, metric.direction
                ),
                "passed": passed,
            })
    if not comparisons:
        raise GateInputError("holdout comparison produced no metric results")
    return comparisons


def hash_json_input(path: Path, label: str) -> str:
    if not path.is_file():
        raise GateInputError(f"{label}: file does not exist: {path}")
    return sha256_file(path)


def evaluate(
    manifest_path: Path,
    candidate_path: Path,
    baseline_path: Path,
    data_root: Path,
    verify_files: str,
) -> JsonObject:
    manifest = parse_manifest(manifest_path)
    baseline_bytes, baseline_hash = read_bytes_with_hash(baseline_path, "baseline")
    if baseline_hash != manifest.accepted_baseline_sha256:
        raise GateInputError(
            "baseline.sha256: accepted baseline does not match manifest pin; "
            f"expected {manifest.accepted_baseline_sha256}, got {baseline_hash}"
        )
    baseline_payload = parse_json_bytes(baseline_bytes, "baseline")
    candidate_rows = parse_summary(candidate_path, "candidate")
    baseline_rows = parse_summary_payload(baseline_payload, "baseline")
    validate_summary_corpus(candidate_rows, manifest, "candidate")
    validate_summary_corpus(baseline_rows, manifest, "baseline")

    verified: list[JsonObject] = []
    for case in manifest.cases:
        selected = verify_files == "all" or (
            verify_files == "holdout" and case.role == "holdout"
        )
        if selected:
            verified.extend(verify_case_files(case, candidate_rows[case.stem], data_root))

    comparisons = compare_holdout(manifest, candidate_rows, baseline_rows)
    passed = all(bool(row["passed"]) for row in comparisons)
    calibration_count = sum(case.role == "calibration" for case in manifest.cases)
    holdout_count = sum(case.role == "holdout" for case in manifest.cases)
    return {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "gate": "negaflow-profile-quality",
        "status": "passed" if passed else "regression",
        "passed": passed,
        "corpusVersion": manifest.corpus_version,
        "inputHashes": {
            "manifest": hash_json_input(manifest_path, "manifest"),
            "candidateSummary": hash_json_input(candidate_path, "candidate"),
            "acceptedBaselineSummary": baseline_hash,
        },
        "verificationMode": verify_files,
        "counts": {
            "calibrationCases": calibration_count,
            "holdoutCases": holdout_count,
            "metricRules": len(manifest.metrics),
            "comparisons": len(comparisons),
            "verifiedFiles": len(verified),
            "regressions": sum(not bool(row["passed"]) for row in comparisons),
        },
        "verifiedFiles": verified,
        "comparisons": comparisons,
        "errors": [],
    }


def invalid_report(error: Exception, verify_files: str) -> JsonObject:
    return {
        "schemaVersion": REPORT_SCHEMA_VERSION,
        "gate": "negaflow-profile-quality",
        "status": "invalid",
        "passed": False,
        "verificationMode": verify_files,
        "errors": [str(error)],
    }


def write_report(path: Path, report: JsonObject) -> None:
    encoded = json.dumps(
        report,
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
        allow_nan=False,
    ) + "\n"
    temporary: Path | None = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as handle:
            handle.write(encoded)
            temporary = Path(handle.name)
        temporary.replace(path)
    except OSError as error:
        if temporary is not None:
            try:
                temporary.unlink(missing_ok=True)
            except OSError:
                pass
        raise GateInputError(f"report: cannot write {path}: {error}") from error


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare a profile-quality candidate against an accepted holdout baseline."
    )
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--candidate-summary", type=Path, required=True)
    parser.add_argument("--baseline-summary", type=Path, required=True)
    parser.add_argument(
        "--data-root",
        type=Path,
        help="Root for manifest file paths (default: manifest directory).",
    )
    parser.add_argument(
        "--verify-files",
        choices=("all", "holdout", "none"),
        default="all",
        help="Hash all files, holdout files, or no image files (default: all).",
    )
    parser.add_argument("--report", type=Path, help="Also atomically write the JSON report.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    data_root = args.data_root if args.data_root is not None else args.manifest.parent
    try:
        report = evaluate(
            args.manifest,
            args.candidate_summary,
            args.baseline_summary,
            data_root,
            args.verify_files,
        )
        exit_code = 0 if bool(report["passed"]) else 1
    except (GateInputError, OSError) as error:
        report = invalid_report(error, args.verify_files)
        exit_code = 2

    if args.report is not None:
        try:
            write_report(args.report, report)
        except GateInputError as error:
            report = invalid_report(error, args.verify_files)
            exit_code = 2
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True, allow_nan=False))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
