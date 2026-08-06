#!/usr/bin/env python3
"""Regenerates the C++ parity fixture header from the macOS ColorSync baseline.

The baseline JSON is the single source of truth. The native probe cannot parse
JSON, because the native tree carries no third-party runtime dependency, so the
patch inputs and the ColorSync reference outputs are emitted as a header instead.

Run this whenever Negaflow.Windows/baseline/colorsync-icm-parity-v1.json changes:

    py Negaflow.Windows/scripts/generate_colorsync_parity_fixture.py
"""

from __future__ import annotations

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
BASELINE = ROOT / "Negaflow.Windows/baseline/colorsync-icm-parity-v1.json"
HEADER = ROOT / "Negaflow.Windows/tests/fixtures/v1/colorsync_icm_parity_fixture.h"


def cxx_float(value: float) -> str:
    """Formats a C++ float literal.

    A literal needs a '.' or an exponent before the F suffix, so a value that
    formats as "0" or "1" must not become "0F" / "1F", which does not compile.
    """
    text = f"{value:.9g}"
    if "." not in text and "e" not in text and "E" not in text:
        text += ".0"
    return text + "F"


def main() -> None:
    doc = json.loads(BASELINE.read_text(encoding="utf-8"))
    patches = doc["patches"]

    lines: list[str] = [
        "#pragma once",
        "",
        "// Generated from Negaflow.Windows/baseline/colorsync-icm-parity-v1.json by",
        "// Negaflow.Windows/scripts/generate_colorsync_parity_fixture.py.",
        "// Do not edit by hand.",
        "//",
        "// `source` holds the 16-bit integers both colour management systems receive,",
        "// recovered as round(in * 65535) exactly as the synthesis rule requires.",
        "// `macos_linear` holds the ColorSync reference output in linear-sRGB float.",
        "",
        "#include <array>",
        "#include <cstddef>",
        "#include <cstdint>",
        "#include <string_view>",
        "",
        "namespace negaflow::fixtures {",
        "",
        "inline constexpr std::string_view colorsync_icm_parity_fixture_id =",
        f'    "{doc["fixtureId"]}";',
        "inline constexpr std::string_view colorsync_icm_parity_profile_sha256 =",
        f'    "{doc["profile"]["sha256"]}";',
        "inline constexpr std::size_t colorsync_icm_parity_profile_bytes =",
        f'    {doc["profile"]["byteCount"]}U;',
        "inline constexpr std::string_view colorsync_icm_parity_operating_system =",
        f'    "{doc["operatingSystem"]}";',
        "inline constexpr std::string_view colorsync_icm_parity_source_commit =",
        f'    "{doc["sourceCommit"]}";',
        "",
        "struct ColorSyncParityPatch final {",
        "    std::string_view name;",
        "    std::array<std::uint16_t, 3> source;",
        "    std::array<float, 3> macos_linear;",
        "};",
        "",
        f"inline constexpr std::array<ColorSyncParityPatch, {len(patches)}>",
        "    colorsync_icm_parity_patches{{",
    ]

    for patch in patches:
        source = [round(value * 65535.0) for value in patch["in"]]
        lines.append("        {")
        lines.append(f'            "{patch["name"]}",')
        lines.append("            {" + ", ".join(f"{v}U" for v in source) + "},")
        lines.append("            {" + ", ".join(cxx_float(v) for v in patch["out"]) + "},")
        lines.append("        },")

    lines.append("    }};")
    lines.append("")
    lines.append("}  // namespace negaflow::fixtures")
    lines.append("")

    HEADER.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"wrote {HEADER.relative_to(ROOT).as_posix()} with {len(patches)} patches")


if __name__ == "__main__":
    main()
