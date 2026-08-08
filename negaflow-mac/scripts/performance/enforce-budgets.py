#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import os
import tempfile
from pathlib import Path
from typing import Any


class InvalidEvidence(ValueError):
    pass


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidEvidence(f"{path}: unreadable JSON: {error}") from error
    if not isinstance(value, dict):
        raise InvalidEvidence(f"{path}: root must be an object")
    return value


def finite_nonnegative(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidEvidence(f"{label}: expected a number")
    number = float(value)
    if not math.isfinite(number) or number < 0:
        raise InvalidEvidence(f"{label}: expected a finite non-negative number")
    return number


def evaluate(budget_path: Path, report_directory: Path) -> dict[str, Any]:
    budget = load_object(budget_path)
    if budget.get("schemaVersion") != 1:
        raise InvalidEvidence("budget: unsupported schemaVersion")
    policy = budget.get("policy")
    if not isinstance(policy, str) or not policy:
        raise InvalidEvidence("budget: policy is required")
    applicability = budget.get("applicability")
    if not isinstance(applicability, dict):
        raise InvalidEvidence("budget: applicability is required")
    expected_architecture = applicability.get("architecture")
    minimum_memory = finite_nonnegative(
        applicability.get("minimumPhysicalMemoryBytes"),
        "budget.applicability.minimumPhysicalMemoryBytes",
    )
    reports = budget.get("reports")
    if not isinstance(reports, dict) or not reports:
        raise InvalidEvidence("budget: reports must be a non-empty object")

    comparisons: list[dict[str, Any]] = []
    failures: list[str] = []
    observed_environment: dict[str, Any] | None = None

    for report_name, rules in reports.items():
        if not isinstance(report_name, str) or Path(report_name).name != report_name:
            raise InvalidEvidence("budget: report names must be plain file names")
        if not isinstance(rules, list) or not rules:
            raise InvalidEvidence(f"budget: {report_name} rules must be non-empty")
        report = load_object(report_directory / report_name)
        if report.get("schemaVersion") != 1 or report.get("configuration") != "release":
            raise InvalidEvidence(f"{report_name}: invalid report contract")
        environment = report.get("environment")
        if not isinstance(environment, dict):
            raise InvalidEvidence(f"{report_name}: environment is required")
        if observed_environment is None:
            observed_environment = environment
        architecture = environment.get("architecture")
        physical_memory = finite_nonnegative(
            environment.get("physicalMemoryBytes"),
            f"{report_name}.environment.physicalMemoryBytes",
        )
        if architecture != expected_architecture:
            raise InvalidEvidence(
                f"{report_name}: architecture {architecture!r} does not match {expected_architecture!r}"
            )
        if physical_memory < minimum_memory:
            raise InvalidEvidence(
                f"{report_name}: physical memory {physical_memory:.0f} is below applicability floor {minimum_memory:.0f}"
            )

        cases = report.get("cases")
        if not isinstance(cases, list):
            raise InvalidEvidence(f"{report_name}: cases must be an array")
        seen: set[tuple[str, int]] = set()
        for index, rule in enumerate(rules):
            if not isinstance(rule, dict):
                raise InvalidEvidence(f"budget: {report_name} rule {index} must be an object")
            scenario = rule.get("scenario")
            frame_count = rule.get("frameCount")
            if not isinstance(scenario, str) or not scenario:
                raise InvalidEvidence(f"budget: {report_name} rule {index} has invalid scenario")
            if isinstance(frame_count, bool) or not isinstance(frame_count, int) or frame_count <= 0:
                raise InvalidEvidence(f"budget: {report_name} rule {index} has invalid frameCount")
            key = (scenario, frame_count)
            if key in seen:
                raise InvalidEvidence(f"budget: duplicate rule {report_name} {key}")
            seen.add(key)
            matches = [
                case for case in cases
                if isinstance(case, dict)
                and case.get("scenario") == scenario
                and case.get("frameCount") == frame_count
            ]
            if len(matches) != 1:
                raise InvalidEvidence(f"{report_name}: expected exactly one case for {key}")
            case = matches[0]
            metrics = (
                ("p95Milliseconds", case.get("durationMilliseconds", {}).get("p95"), rule.get("p95MaximumMilliseconds")),
                ("maxRSSAfterBytes", case.get("memory", {}).get("maxRSSAfterBytes"), rule.get("maxRSSAfterMaximumBytes")),
                ("bytesPerFrame", case.get("bytesPerFrame"), rule.get("bytesPerFrameMaximum")),
            )
            for metric, observed_raw, maximum_raw in metrics:
                if maximum_raw is None:
                    continue
                observed = finite_nonnegative(observed_raw, f"{report_name}.{key}.{metric}")
                maximum = finite_nonnegative(maximum_raw, f"budget.{report_name}.{key}.{metric}")
                passed = observed <= maximum
                comparison = {
                    "report": report_name,
                    "scenario": scenario,
                    "frameCount": frame_count,
                    "metric": metric,
                    "observed": observed,
                    "maximum": maximum,
                    "passed": passed,
                }
                comparisons.append(comparison)
                if not passed:
                    failures.append(
                        f"{report_name} {scenario} {frame_count} {metric}: {observed} > {maximum}"
                    )

    return {
        "schemaVersion": 1,
        "policy": policy,
        "status": "pass" if not failures else "fail",
        "environment": observed_environment,
        "comparisons": comparisons,
        "failures": failures,
    }


def write_atomic(path: Path, document: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(document, indent=2, sort_keys=True) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--budget", type=Path, required=True)
    parser.add_argument("--report-directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = evaluate(args.budget, args.report_directory)
        write_atomic(args.output, result)
    except InvalidEvidence as error:
        print(f"[performance-budget] invalid evidence: {error}")
        return 2
    if result["status"] != "pass":
        for failure in result["failures"]:
            print(f"[performance-budget] FAIL: {failure}")
        return 1
    print(f"[performance-budget] PASS: {len(result['comparisons'])} comparisons")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
