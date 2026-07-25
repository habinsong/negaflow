#!/usr/bin/env python3
"""Fail-closed aggregate no-regression gate for the pinned FILM-R v2 report."""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from pathlib import Path
from typing import Any


class InvalidEvidence(ValueError):
    pass


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise InvalidEvidence(f"{path}: unreadable JSON: {error}") from error


def finite_number(value: Any, label: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidEvidence(f"{label}: expected a number")
    number = float(value)
    if not math.isfinite(number):
        raise InvalidEvidence(f"{label}: expected a finite number")
    return number


def positive_integer(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise InvalidEvidence(f"{label}: expected a positive integer")
    return value


def evaluate(config_path: Path, report_path: Path) -> dict[str, Any]:
    config = load_json(config_path)
    report = load_json(report_path)
    if not isinstance(config, dict) or config.get("schemaVersion") != 1:
        raise InvalidEvidence("config: unsupported schemaVersion")
    if not isinstance(report, list):
        raise InvalidEvidence("report: root must be an array")
    corpus = config.get("corpus")
    baseline = config.get("baseline")
    tolerance = config.get("tolerance")
    if not all(isinstance(value, dict) for value in (corpus, baseline, tolerance)):
        raise InvalidEvidence("config: corpus, baseline, and tolerance are required")
    quality_floor = config.get("qualityFloor")
    if quality_floor is not None and not isinstance(quality_floor, dict):
        raise InvalidEvidence("config: qualityFloor must be an object")
    expected_count = positive_integer(corpus.get("expectedPairCount"), "corpus.expectedPairCount")
    expected_sensitivity = finite_number(corpus.get("sensitivity"), "corpus.sensitivity")
    if len(report) != expected_count:
        raise InvalidEvidence(f"report: expected {expected_count} entries, found {len(report)}")

    names: set[str] = set()
    psnr_deltas: list[float] = []
    pixel_counts: list[int] = []
    improved_fractions: list[float] = []
    regressed_fractions: list[float] = []
    changed_counts: list[int] = []
    for index, entry in enumerate(report):
        label = f"report[{index}]"
        if not isinstance(entry, dict):
            raise InvalidEvidence(f"{label}: expected an object")
        name = entry.get("imageName")
        if not isinstance(name, str) or not name or name in names:
            raise InvalidEvidence(f"{label}.imageName: expected a unique non-empty string")
        names.add(name)
        sensitivity = finite_number(entry.get("sensitivity"), f"{label}.sensitivity")
        if sensitivity != expected_sensitivity:
            raise InvalidEvidence(
                f"{label}.sensitivity: expected {expected_sensitivity}, found {sensitivity}"
            )
        width = positive_integer(entry.get("width"), f"{label}.width")
        height = positive_integer(entry.get("height"), f"{label}.height")
        reference = entry.get("referenceMetrics")
        if not isinstance(reference, dict):
            raise InvalidEvidence(f"{label}.referenceMetrics: required")
        psnr_deltas.append(finite_number(reference.get("psnrDelta"), f"{label}.psnrDelta"))
        improved_fractions.append(finite_number(
            reference.get("improvedPixelFraction"), f"{label}.improvedPixelFraction"
        ))
        regressed_fractions.append(finite_number(
            reference.get("regressedPixelFraction"), f"{label}.regressedPixelFraction"
        ))
        changed = entry.get("changedPixelCount")
        if isinstance(changed, bool) or not isinstance(changed, int) or changed < 0:
            raise InvalidEvidence(f"{label}.changedPixelCount: expected a non-negative integer")
        pixel_counts.append(width * height)
        changed_counts.append(changed)

    total_pixels = sum(pixel_counts)
    observed = {
        "improvedImageCount": sum(value > 0 for value in psnr_deltas),
        "regressedImageCount": sum(value < 0 for value in psnr_deltas),
        "meanPSNRDelta": statistics.fmean(psnr_deltas),
        "medianPSNRDelta": statistics.median(psnr_deltas),
        "worstPSNRDelta": min(psnr_deltas),
        "weightedImprovedPixelFraction": sum(
            value * count for value, count in zip(improved_fractions, pixel_counts)
        ) / total_pixels,
        "weightedRegressedPixelFraction": sum(
            value * count for value, count in zip(regressed_fractions, pixel_counts)
        ) / total_pixels,
        "changedPixelFraction": sum(changed_counts) / total_pixels,
    }
    psnr_tolerance = finite_number(tolerance.get("psnrDB"), "tolerance.psnrDB")
    pixel_tolerance = finite_number(
        tolerance.get("pixelFraction"), "tolerance.pixelFraction"
    )
    failures: list[str] = []

    def minimum(metric: str, tolerance_value: float = 0) -> None:
        required = finite_number(baseline.get(metric), f"baseline.{metric}") - tolerance_value
        if observed[metric] < required:
            failures.append(f"{metric}: {observed[metric]} < {required}")

    def maximum(metric: str, tolerance_value: float = 0) -> None:
        allowed = finite_number(baseline.get(metric), f"baseline.{metric}") + tolerance_value
        if observed[metric] > allowed:
            failures.append(f"{metric}: {observed[metric]} > {allowed}")

    minimum("improvedImageCount")
    maximum("regressedImageCount")
    minimum("meanPSNRDelta", psnr_tolerance)
    minimum("medianPSNRDelta", psnr_tolerance)
    minimum("worstPSNRDelta", psnr_tolerance)
    minimum("weightedImprovedPixelFraction", pixel_tolerance)
    maximum("weightedRegressedPixelFraction", pixel_tolerance)
    maximum("changedPixelFraction", pixel_tolerance)

    if quality_floor is not None:
        def floor_minimum(metric: str) -> None:
            required = finite_number(quality_floor.get(metric), f"qualityFloor.{metric}")
            if observed[metric] < required:
                failures.append(f"{metric}: {observed[metric]} < quality floor {required}")

        def floor_maximum(metric: str) -> None:
            allowed = finite_number(quality_floor.get(metric), f"qualityFloor.{metric}")
            if observed[metric] > allowed:
                failures.append(f"{metric}: {observed[metric]} > quality floor {allowed}")

        floor_minimum("improvedImageCount")
        floor_maximum("regressedImageCount")
        floor_minimum("meanPSNRDelta")
        floor_minimum("medianPSNRDelta")
        floor_minimum("worstPSNRDelta")
        floor_minimum("weightedImprovedPixelFraction")
        floor_maximum("weightedRegressedPixelFraction")
        floor_maximum("changedPixelFraction")
    return {
        "schemaVersion": 1,
        "policy": config.get("policy"),
        "status": "pass" if not failures else "fail",
        "corpus": corpus,
        "observed": observed,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        result = evaluate(args.config, args.report)
    except InvalidEvidence as error:
        print(f"[software-defect-quality] invalid evidence: {error}", file=sys.stderr)
        return 2
    encoded = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_name(f".{args.output.name}.tmp")
        temporary.write_text(encoded, encoding="utf-8")
        temporary.replace(args.output)
    print(encoded, end="")
    return 0 if result["status"] == "pass" else 1


if __name__ == "__main__":
    raise SystemExit(main())
