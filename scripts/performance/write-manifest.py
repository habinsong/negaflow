#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import platform
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("core", "full"), required=True)
    parser.add_argument("--directory", type=Path, required=True)
    args = parser.parse_args()

    reports = sorted(
        path.name for path in args.directory.glob("*.json")
        if path.name != "manifest.json"
    )
    document = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "mode": args.mode,
        "portableTimingGateApplied": False,
        "releaseConfiguration": True,
        "environment": {
            "machine": platform.machine(),
            "macOS": platform.mac_ver()[0],
        },
        "completedGates": [
            "library-query",
            "whole-catalog-json",
            "sqlite-catalog",
            "high-resolution-interaction",
            "guided-defect",
        ] + (["real-pixel-roll"] if args.mode == "full" else []),
        "reports": reports,
    }
    destination = args.directory / "manifest.json"
    destination.write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
