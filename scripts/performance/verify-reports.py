#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any


def load_report(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"{path}: report root must be an object")
    return value


def verify_report(path: Path, expected_kind: str) -> None:
    report = load_report(path)
    if report.get("schemaVersion") != 1:
        raise ValueError(f"{path}: unsupported schemaVersion")
    if report.get("configuration") != "release":
        raise ValueError(f"{path}: benchmark must use release configuration")
    if report.get("timingGateApplied") is not False:
        raise ValueError(f"{path}: portable reports must not claim a timing gate")

    cases = report.get("cases")
    if not isinstance(cases, list) or not cases:
        raise ValueError(f"{path}: cases must be a non-empty array")
    for index, case in enumerate(cases):
        if not isinstance(case, dict):
            raise ValueError(f"{path}: case {index} must be an object")
        samples = case.get("durationMilliseconds", {}).get("samples")
        if not isinstance(samples, list) or not samples:
            raise ValueError(f"{path}: case {index} has no duration samples")
        if any(not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0
               for value in samples):
            raise ValueError(f"{path}: case {index} contains an invalid duration")
        if not isinstance(case.get("frameCount"), int) or case["frameCount"] <= 0:
            raise ValueError(f"{path}: case {index} has an invalid frame count")

    if expected_kind == "catalog":
        if report.get("storageKind") != "whole-catalog-json-snapshot":
            raise ValueError(f"{path}: unexpected catalog storage kind")
        scenarios = {case.get("scenario") for case in cases}
        required = {"json-encode", "json-decode", "atomic-write-new-primary", "primary-file-load"}
        if not required.issubset(scenarios):
            raise ValueError(f"{path}: catalog scenarios are incomplete")
    elif expected_kind == "query":
        if not isinstance(report.get("queryVersion"), int):
            raise ValueError(f"{path}: queryVersion is missing")
    elif expected_kind == "sqlite-catalog":
        if report.get("storageKind") != "sqlite-row-store-v1":
            raise ValueError(f"{path}: unexpected SQLite catalog storage kind")
        scenarios = {case.get("scenario") for case in cases}
        required = {"sqlite-upsert-commit", "sqlite-primary-load", "sqlite-no-change-commit"}
        if not required.issubset(scenarios):
            raise ValueError(f"{path}: SQLite catalog scenarios are incomplete")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--query", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--sqlite-catalog", type=Path, required=True)
    args = parser.parse_args()
    verify_report(args.query, "query")
    verify_report(args.catalog, "catalog")
    verify_report(args.sqlite_catalog, "sqlite-catalog")
    print("[performance] report contracts verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
