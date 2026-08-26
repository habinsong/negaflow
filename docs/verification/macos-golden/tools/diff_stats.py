#!/usr/bin/env python3
"""Difference distribution between two 16-bit TIFFs (GrainMend on vs off).

    python3 diff_stats.py <a.tif> <b.tif> [--json]

Reports two views of |a - b| in 16-bit code values:
  perPixelMaxChannel — one number per pixel = max over R,G,B
  pooledChannel      — every channel sample treated as its own observation
For each: p50, p90, p99, p99.9, max, the count of samples over 100, and that
count as a share of the total.
"""
import json
import sys

import numpy as np
import tifffile

# tifffile (not PIL) — PIL down-converts 16-bit RGB TIFFs to 8 bits.
THRESHOLD = 100


def describe(values, label):
    total = int(values.size)
    over = int(np.count_nonzero(values > THRESHOLD))
    percentiles = np.percentile(values, [50, 90, 99, 99.9])
    return {
        "view": label,
        "sampleCount": total,
        "p50": float(percentiles[0]),
        "p90": float(percentiles[1]),
        "p99": float(percentiles[2]),
        "p99_9": float(percentiles[3]),
        "max": int(values.max()),
        "mean": float(values.mean()),
        "nonZeroCount": int(np.count_nonzero(values)),
        "nonZeroPercent": 100.0 * np.count_nonzero(values) / total,
        "over%dCount" % THRESHOLD: over,
        "over%dPercent" % THRESHOLD: 100.0 * over / total,
    }


def main(argv):
    files = [a for a in argv[1:] if not a.startswith("--")]
    if len(files) != 2:
        raise SystemExit(__doc__)
    first = tifffile.imread(files[0]).astype(np.int32)
    second = tifffile.imread(files[1]).astype(np.int32)
    if first.shape != second.shape:
        raise SystemExit("shape mismatch: %s vs %s" % (first.shape, second.shape))

    delta = np.abs(first - second)
    rgb = delta[:, :, :3] if delta.ndim == 3 else delta[:, :, None]
    report = {
        "a": files[0],
        "b": files[1],
        "shape": list(first.shape),
        "views": [
            describe(rgb.max(axis=2).ravel(), "perPixelMaxChannel"),
            describe(rgb.ravel(), "pooledChannel"),
        ],
    }
    if "--json" in argv:
        print(json.dumps(report, indent=2, sort_keys=True))
        return
    print("%s\nvs %s  shape=%s" % (files[0], files[1], first.shape))
    for view in report["views"]:
        print("  [%s] n=%d" % (view["view"], view["sampleCount"]))
        print("     p50=%.0f p90=%.0f p99=%.0f p99.9=%.0f max=%d mean=%.3f"
              % (view["p50"], view["p90"], view["p99"], view["p99_9"],
                 view["max"], view["mean"]))
        print("     >100: %d (%.4f%%)   nonzero: %d (%.4f%%)"
              % (view["over100Count"], view["over100Percent"],
                 view["nonZeroCount"], view["nonZeroPercent"]))


if __name__ == "__main__":
    main(sys.argv)
