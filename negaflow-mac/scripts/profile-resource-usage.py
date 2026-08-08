#!/usr/bin/env python3
"""Run a command while sampling its process tree and macOS GPU statistics."""

from __future__ import annotations

import argparse
import json
import math
import re
import resource
import statistics
import subprocess
import sys
import time
from pathlib import Path


GPU_VALUE_PATTERNS = {
    "device_percent": re.compile(r'"Device Utilization %"=(\d+)'),
    "renderer_percent": re.compile(r'"Renderer Utilization %"=(\d+)'),
    "tiler_percent": re.compile(r'"Tiler Utilization %"=(\d+)'),
    "memory_bytes": re.compile(r'"In use system memory"=(\d+)'),
}


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, math.ceil(fraction * len(ordered)) - 1))
    return ordered[index]


def process_tree_usage(root_pid: int) -> tuple[float, int, int]:
    try:
        output = subprocess.check_output(
            ["ps", "-axo", "pid=,ppid=,%cpu=,rss="],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return 0.0, 0, 0

    rows: list[tuple[int, int, float, int]] = []
    children: dict[int, list[int]] = {}
    usage: dict[int, tuple[float, int]] = {}
    for line in output.splitlines():
        fields = line.split()
        if len(fields) != 4:
            continue
        try:
            pid, ppid = int(fields[0]), int(fields[1])
            cpu, rss_kib = float(fields[2]), int(fields[3])
        except ValueError:
            continue
        rows.append((pid, ppid, cpu, rss_kib))
        children.setdefault(ppid, []).append(pid)
        usage[pid] = (cpu, rss_kib)

    descendants = {root_pid}
    pending = [root_pid]
    while pending:
        parent = pending.pop()
        for child in children.get(parent, []):
            if child not in descendants:
                descendants.add(child)
                pending.append(child)
    cpu_total = sum(usage.get(pid, (0.0, 0))[0] for pid in descendants)
    rss_total = sum(usage.get(pid, (0.0, 0))[1] for pid in descendants) * 1024
    return cpu_total, rss_total, len(descendants)


def gpu_usage() -> dict[str, int] | None:
    try:
        output = subprocess.check_output(
            ["ioreg", "-r", "-d", "1", "-c", "IOAccelerator"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    values: dict[str, int] = {}
    for key, pattern in GPU_VALUE_PATTERNS.items():
        match = pattern.search(output)
        if match:
            values[key] = int(match.group(1))
    return values or None


def summary(values: list[float]) -> dict[str, float]:
    return {
        "mean": statistics.fmean(values) if values else 0.0,
        "p95": percentile(values, 0.95),
        "max": max(values, default=0.0),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--interval", type=float, default=0.2)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or args.interval <= 0:
        parser.error("a command and positive --interval are required")

    idle_gpu = gpu_usage()
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic()
    process = subprocess.Popen(command)
    cpu_samples: list[float] = []
    rss_samples: list[float] = []
    process_count_samples: list[float] = []
    gpu_samples: dict[str, list[float]] = {key: [] for key in GPU_VALUE_PATTERNS}

    try:
        while process.poll() is None:
            cpu, rss, process_count = process_tree_usage(process.pid)
            cpu_samples.append(cpu)
            rss_samples.append(float(rss))
            process_count_samples.append(float(process_count))
            gpu = gpu_usage()
            if gpu:
                for key, value in gpu.items():
                    gpu_samples[key].append(float(value))
            time.sleep(args.interval)
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        raise

    return_code = process.wait()
    elapsed = time.monotonic() - started
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    user_seconds = max(0.0, after.ru_utime - before.ru_utime)
    system_seconds = max(0.0, after.ru_stime - before.ru_stime)
    report = {
        "schemaVersion": 1,
        "command": command,
        "returnCode": return_code,
        "sampleIntervalSeconds": args.interval,
        "sampleCount": len(cpu_samples),
        "elapsedSeconds": elapsed,
        "cpu": {
            "sampledProcessTreePercent": summary(cpu_samples),
            "sampledProcessTreeScope": "target command process tree only",
            "userSeconds": user_seconds,
            "systemSeconds": system_seconds,
            "monitorAndCommandChildrenAveragePercentFromCPUTime": (
                (user_seconds + system_seconds) / elapsed * 100 if elapsed > 0 else 0
            ),
        },
        "memory": {
            "sampledProcessTreeRSSBytes": summary(rss_samples),
            "monitorAndCommandChildrenMaximumResidentSetBytes": int(after.ru_maxrss),
            "sampledProcessCount": summary(process_count_samples),
        },
        "gpu": {
            "scope": "system-wide IOAccelerator while the isolated command ran",
            "idleBefore": idle_gpu,
            **{key: summary(values) for key, values in gpu_samples.items()},
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return return_code


if __name__ == "__main__":
    sys.exit(main())
