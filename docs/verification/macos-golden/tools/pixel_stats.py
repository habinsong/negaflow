#!/usr/bin/env python3
"""Per-channel pixel statistics for the exported 16-bit golden TIFFs.

    python3 pixel_stats.py <dir-or-file> [...]

Prints, and emits JSON on --json, the per-channel min / median / max / mean in
raw 16-bit code values (0..65535).
"""
import json
import os
import sys

import numpy as np
import tifffile

# PIL silently down-converts 16-bit RGB TIFFs to 8 bits, which would report code
# values in 0..255. tifffile returns the real uint16 samples.


def stats(path):
    array = tifffile.imread(path)
    if array.ndim == 2:
        array = array[:, :, None]
    channels = "RGBA"[:array.shape[2]]
    report = {
        "file": os.path.basename(path),
        "bytes": os.path.getsize(path),
        "width": int(array.shape[1]),
        "height": int(array.shape[0]),
        "dtype": str(array.dtype),
        "channels": {},
    }
    for index, name in enumerate(channels):
        plane = array[:, :, index]
        report["channels"][name] = {
            "min": int(plane.min()),
            "median": float(np.median(plane)),
            "max": int(plane.max()),
            "mean": float(plane.mean()),
        }
    return report


def collect(paths):
    files = []
    for path in paths:
        if os.path.isdir(path):
            files += [os.path.join(path, n) for n in sorted(os.listdir(path))
                      if n.lower().endswith((".tif", ".tiff"))]
        else:
            files.append(path)
    return files


def main(argv):
    as_json = "--json" in argv
    files = collect([a for a in argv[1:] if not a.startswith("--")])
    reports = [stats(path) for path in files]
    if as_json:
        print(json.dumps(reports, indent=2, sort_keys=True))
        return
    header = "%-44s %-11s %s" % ("file", "size", "ch  min   median      max        mean")
    print(header)
    for report in reports:
        print("%-44s %dx%d" % (report["file"], report["width"], report["height"]))
        for name, value in report["channels"].items():
            print("  %-42s %s %6d %9.1f %8d %11.3f" % (
                "", name, value["min"], value["median"], value["max"], value["mean"]))


if __name__ == "__main__":
    main(sys.argv)
