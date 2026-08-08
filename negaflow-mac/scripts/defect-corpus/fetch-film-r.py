#!/usr/bin/env python3
"""Fetch the pinned FILM-R corpus from Figshare and verify every downloaded byte."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import Request, urlopen


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = REPOSITORY_ROOT / "Config" / "defect-corpus-film-r-v2.json"
DEFAULT_OUTPUT = REPOSITORY_ROOT / "build" / "defect-corpus" / "film-r-v2"
USER_AGENT = "negaflow-Defect-Corpus/1.0 (+https://github.com/)"


def open_url(url: str, timeout: int):
    return urlopen(Request(url, headers={"User-Agent": USER_AGENT}), timeout=timeout)


def read_json(url: str) -> dict:
    with open_url(url, timeout=30) as response:
        return json.load(response)


def file_digest(path: Path) -> str:
    digest = hashlib.md5()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_metadata(metadata: dict, config: dict) -> dict[str, dict]:
    if metadata.get("doi") != config["doi"]:
        raise RuntimeError(f"unexpected DOI: {metadata.get('doi')}")
    if metadata.get("license", {}).get("name") != config["license"]:
        raise RuntimeError(f"unexpected license: {metadata.get('license')}")

    files = metadata.get("files", [])
    if sum(item["size"] for item in files) != config["expectedTotalBytes"]:
        raise RuntimeError("Figshare byte total differs from the pinned corpus contract")
    by_name = {item["name"]: item for item in files}
    damaged = {name[:-4] for name in by_name if name.endswith(".jpg") and not name.endswith("_restored.jpg")}
    restored = {name[:-13] for name in by_name if name.endswith("_restored.jpg")}
    if damaged != restored or len(damaged) != config["expectedPairCount"]:
        raise RuntimeError("Figshare damaged/restored pair set differs from the pinned corpus contract")
    return by_name


def download(item: dict, output: Path) -> None:
    destination = output / item["name"]
    if destination.exists() and destination.stat().st_size == item["size"]:
        if file_digest(destination) == item["supplied_md5"]:
            print(f"[verified] {item['name']}")
            return

    source = item["download_url"]
    if urlparse(source).scheme != "https" or urlparse(source).hostname != "ndownloader.figshare.com":
        raise RuntimeError(f"untrusted download URL: {source}")
    temporary = destination.with_suffix(destination.suffix + ".partial")
    temporary.unlink(missing_ok=True)
    subprocess.run(
        [
            "curl", "--location", "--fail", "--silent", "--show-error",
            "--retry", "8", "--retry-all-errors", "--retry-delay", "2",
            "--proto", "=https", "--output", str(temporary), source,
        ],
        check=True,
    )
    if temporary.stat().st_size != item["size"] or file_digest(temporary) != item["supplied_md5"]:
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"integrity check failed: {item['name']}")
    os.replace(temporary, destination)
    print(f"[downloaded] {item['name']}")


def extract_archive(archive: Path, items: list[dict], output: Path) -> None:
    with zipfile.ZipFile(archive) as source:
        members = {info.filename: info for info in source.infolist() if not info.is_dir()}
        expected = {item["name"] for item in items}
        missing = sorted(expected - members.keys())
        if missing:
            raise RuntimeError(f"archive lacks pinned file(s): {', '.join(missing)}")
        unexpected = sorted(members.keys() - expected)
        if unexpected:
            raise RuntimeError(f"archive contains unexpected file(s): {', '.join(unexpected)}")

        for item in items:
            name = item["name"]
            if Path(name).name != name:
                raise RuntimeError(f"unsafe archive member: {name}")
            destination = output / name
            temporary = destination.with_suffix(destination.suffix + ".partial")
            temporary.unlink(missing_ok=True)
            with source.open(members[name]) as input_handle, temporary.open("wb") as output_handle:
                shutil.copyfileobj(input_handle, output_handle, length=1024 * 1024)
            if temporary.stat().st_size != item["size"] or file_digest(temporary) != item["supplied_md5"]:
                temporary.unlink(missing_ok=True)
                raise RuntimeError(f"archive integrity check failed: {name}")
            os.replace(temporary, destination)
            print(f"[archive] {name}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch the pinned FILM-R v2 GrainMend RGB corpus")
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--case", action="append", default=[], help="base name without .jpg")
    parser.add_argument("--all", action="store_true", help="download all 44 pairs (about 438 MB)")
    parser.add_argument(
        "--archive",
        type=Path,
        help="verify and extract a browser-downloaded Figshare ZIP instead of using its file CDN",
    )
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    api_url = (
        f"https://api.figshare.com/v2/articles/{config['articleID']}"
        f"/versions/{config['articleVersion']}"
    )
    metadata = read_json(api_url)
    by_name = validate_metadata(metadata, config)
    all_cases = sorted(name[:-4] for name in by_name if name.endswith(".jpg") and not name.endswith("_restored.jpg"))
    selected_cases = all_cases if args.all else (args.case or config["smokeCases"])
    unknown_cases = sorted(set(selected_cases) - set(all_cases))
    if unknown_cases:
        raise RuntimeError(f"unknown corpus case(s): {', '.join(unknown_cases)}")

    args.output.mkdir(parents=True, exist_ok=True)
    selected_items = [
        by_name[name]
        for case_name in selected_cases
        for name in (f"{case_name}.jpg", f"{case_name}_restored.jpg")
    ]
    if args.archive:
        extract_archive(args.archive, selected_items, args.output)

    selected_files = []
    for item in selected_items:
        download(item, args.output)
        selected_files.append({key: item[key] for key in ("id", "name", "size", "supplied_md5", "download_url")})

    lock = {
        "schemaVersion": 1,
        "retrievedAt": datetime.now(timezone.utc).isoformat(),
        "sourceAPI": api_url,
        "doi": metadata["doi"],
        "license": metadata["license"],
        "selectedCases": selected_cases,
        "files": selected_files,
    }
    lock_path = args.output / "corpus-lock.json"
    lock_path.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[complete] {len(selected_cases)} pair(s), lock: {lock_path}")


if __name__ == "__main__":
    main()
