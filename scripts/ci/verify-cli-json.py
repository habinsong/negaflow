#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / ".build/debug/negaflow"


def run(*arguments: str, expected_code: int = 0) -> tuple[dict[str, Any], str]:
    completed = subprocess.run(
        [str(BINARY), *arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != expected_code:
        raise AssertionError(
            f"unexpected exit {completed.returncode}: {completed.stderr.strip()}"
        )
    document = json.loads(completed.stdout)
    if completed.stdout.count("\n") != 1:
        raise AssertionError("stdout must contain exactly one newline-terminated JSON document")
    return document, completed.stderr


def verify_envelope(document: dict[str, Any], command: str, status: str) -> None:
    if document.get("schema") != "negaflow.scanner-cli":
        raise AssertionError("unexpected schema")
    if document.get("schemaVersion") != 1:
        raise AssertionError("unexpected schemaVersion")
    if document.get("command") != command or document.get("status") != status:
        raise AssertionError("unexpected command status")


def main() -> int:
    if not BINARY.is_file():
        raise SystemExit(f"missing CLI binary: {BINARY}")

    detected, _ = run("detect", "--demo", "--json")
    verify_envelope(detected, "detect", "ok")
    backends = detected["payload"]["backends"]
    devices = [device for backend in backends for device in backend["devices"]]
    if not devices:
        raise AssertionError("demo detect returned no devices")
    scanner_id = devices[0]["id"]

    capability, _ = run("capabilities", scanner_id, "--demo", "--json")
    verify_envelope(capability, "capabilities", "ok")
    values = capability["payload"]["capabilities"]
    expected_keys = {
        "resolutionsDPI", "modes", "bitDepths", "sourceModes", "transparencyModes",
        "supportsPreview", "supportsTransparency", "supportsInfrared",
        "supportsMultiExposure", "supportsScanArea", "supportsPositionedScanArea",
        "supportsLampWarmupStatus",
        "brightnessRange", "contrastRange", "hardwareExposureRange", "disabledReasons",
        "maxScanArea", "minScanArea", "scanAreaUnit", "outputFormats",
        "scanOriginXRange", "scanOriginYRange", "scanWidthRange", "scanHeightRange",
        "estimatedScanSpeeds",
    }
    if set(values) != expected_keys:
        raise AssertionError(f"capability field drift: {sorted(set(values) ^ expected_keys)}")

    failed, stderr = run("capabilities", "missing-device", "--json", expected_code=2)
    verify_envelope(failed, "capabilities", "error")
    if failed.get("payload") is not None or failed.get("error", {}).get("code") != "invalid_arguments":
        raise AssertionError("invalid argument envelope is malformed")
    if "unknown scanner" not in stderr:
        raise AssertionError("human diagnostic must remain on stderr")

    print("[ci-cli-json] stdout and capability contracts verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
