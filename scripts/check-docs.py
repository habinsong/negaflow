#!/usr/bin/env python3
"""Check the six-language documentation set against the build configuration.

Run from the repository root:

    python3 scripts/check-docs.py

The build scripts and project files are the source of truth. Anything typed by
hand into a document is compared against them, never the other way round.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANGS = ["ko", "ja", "zh-Hans", "fr", "de"]

problems: list[str] = []
notes: list[str] = []


def fail(path: Path | str, message: str) -> None:
    problems.append(f"{path}: {message}")


def note(path: Path | str, message: str) -> None:
    notes.append(f"{path}: {message}")


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


# --------------------------------------------------------------------------
# Values that the documents are checked against.
# --------------------------------------------------------------------------

def build_facts() -> dict[str, str]:
    facts: dict[str, str] = {}

    project = read(ROOT / "negaflow-mac/project.yml")
    match = re.search(r"MARKETING_VERSION:\s*([0-9][0-9.]*)", project)
    if not match:
        fail("negaflow-mac/project.yml", "MARKETING_VERSION not found")
        return facts
    facts["version"] = match.group(1)

    csproj = read(ROOT / "negaflow-windows/src/Shell/Negaflow.Shell.csproj")
    match = re.search(r"<TargetPlatformMinVersion>([0-9.]+)</TargetPlatformMinVersion>", csproj)
    if not match:
        fail("negaflow-windows/src/Shell/Negaflow.Shell.csproj", "TargetPlatformMinVersion not found")
    else:
        facts["win_min_build"] = match.group(1).split(".")[2]

    release = read(ROOT / "negaflow-windows/scripts/build-release.ps1")
    match = re.search(r'\$installerName\s*=\s*"([^"]+)"', release)
    if not match:
        fail("negaflow-windows/scripts/build-release.ps1", "$installerName not found")
    else:
        facts["installer_pattern"] = match.group(1)

    return facts


# --------------------------------------------------------------------------
# Documents under review.
# --------------------------------------------------------------------------

def markdown_files() -> list[Path]:
    """The documents published to readers.

    `docs/local`, `negaflow-windows/docs/windows_docs` and `.../progress` are
    working notes. They are local or internal, so they are left out.
    """
    files = sorted(ROOT.glob("README*.md"))
    files += [ROOT / "AGENTS.md", ROOT / "CONTRIBUTING.md"]
    files += [p for p in sorted((ROOT / "docs").rglob("*.md")) if "local" not in p.parts]
    files += sorted((ROOT / "negaflow-mac/docs").glob("*.md"))
    files += sorted((ROOT / "negaflow-windows/docs").glob("*.md"))
    return [p for p in files if p.exists()]


def language_of(path: Path) -> str:
    name = path.name
    match = re.match(r"README_([A-Za-z-]+)\.md$", name)
    if match:
        return match.group(1)
    parts = path.relative_to(ROOT).parts
    for part in parts:
        if part in LANGS:
            return part
    return "en"


# --------------------------------------------------------------------------
# 1. Release facts
# --------------------------------------------------------------------------

def check_release_facts(facts: dict[str, str], files: list[Path]) -> None:
    version = facts.get("version")
    win_build = facts.get("win_min_build")
    pattern = facts.get("installer_pattern", "")
    expected_installer = (
        pattern.replace("$Version", version or "").replace("$artifactArchitecture", "x64")
        if version
        else ""
    )

    artifact = re.compile(r"negaflow-([0-9][0-9.]*)-([A-Za-z0-9-]+)\.(exe|pkg|dmg|zip)")

    for path in files:
        rel = path.relative_to(ROOT)
        for lineno, line in enumerate(read(path).splitlines(), 1):
            for match in artifact.finditer(line):
                found_version, tail, ext = match.groups()
                if version and found_version != version:
                    fail(f"{rel}:{lineno}", f"release artifact says {found_version}, project.yml says {version}")
                if ext == "exe" and expected_installer and match.group(0) != expected_installer:
                    fail(
                        f"{rel}:{lineno}",
                        f"installer name {match.group(0)} does not match build-release.ps1 ({expected_installer})",
                    )

            if win_build and "Windows 11" in line:
                if "24H2" not in line and win_build not in line:
                    fail(
                        f"{rel}:{lineno}",
                        f"Windows 11 mentioned without the 24H2 / {win_build} minimum",
                    )


# --------------------------------------------------------------------------
# 2. Six-language parity
# --------------------------------------------------------------------------

def check_parity() -> None:
    base = ROOT / "docs"
    english = sorted(
        p.relative_to(base).as_posix()
        for p in base.rglob("*.md")
        if p.relative_to(base).parts[0] not in LANGS and "local" not in p.parts
    )
    for lang in LANGS:
        translated = sorted(
            p.relative_to(base / lang).as_posix() for p in (base / lang).rglob("*.md")
        )
        for missing in set(english) - set(translated):
            fail(f"docs/{lang}", f"missing translation of docs/{missing}")
        for extra in set(translated) - set(english):
            fail(f"docs/{lang}/{extra}", "has no English counterpart")

    for name in english:
        source = base / name
        expected = [h for h in re.findall(r"^(#+) ", read(source), re.M)]
        for lang in LANGS:
            target = base / lang / name
            if not target.exists():
                continue
            actual = [h for h in re.findall(r"^(#+) ", read(target), re.M)]
            if len(actual) != len(expected):
                fail(
                    f"docs/{lang}/{name}",
                    f"{len(actual)} headings, English has {len(expected)}",
                )
            elif actual != expected:
                fail(f"docs/{lang}/{name}", "heading levels differ from the English document")

    readmes = {"en": ROOT / "README.md"}
    readmes.update({lang: ROOT / f"README_{lang}.md" for lang in LANGS})
    counts = {
        lang: len(re.findall(r"^#+ ", read(path), re.M))
        for lang, path in readmes.items()
        if path.exists()
    }
    for lang, count in counts.items():
        if count != counts["en"]:
            fail(f"README_{lang}.md", f"{count} headings, README.md has {counts['en']}")


# --------------------------------------------------------------------------
# 3. Relative links
# --------------------------------------------------------------------------

LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")


def check_links(files: list[Path]) -> None:
    for path in files:
        rel = path.relative_to(ROOT)
        for lineno, line in enumerate(read(path).splitlines(), 1):
            for target in LINK.findall(line):
                if target.startswith(("http://", "https://", "#", "mailto:")):
                    continue
                clean = target.split("#", 1)[0]
                if not clean:
                    continue
                resolved = (path.parent / clean).resolve()
                if not resolved.exists():
                    fail(f"{rel}:{lineno}", f"broken link {target}")


# --------------------------------------------------------------------------
# 4. Machine-written phrasing
# --------------------------------------------------------------------------

BANNED = {
    "en": [
        r"\bdelve\b", r"\bseamless(ly)?\b", r"\brobust\b", r"\bcomprehensive\b",
        r"\bleverage[sd]?\b", r"\bharness(es|ed)?\b", r"\butiliz(e|es|ed|ing)\b",
        r"\bshowcas(e|es|ed|ing)\b", r"\belevat(e|es|ed|ing)\b", r"\bempower(s|ed)?\b",
        r"\bunlock(s|ed|ing)?\b", r"\bfoster(s|ed|ing)?\b", r"\bboasts\b",
        r"\bcrucial\b", r"\bpivotal\b", r"\bmeticulous(ly)?\b", r"\bintricate\b",
        r"\bnuanced\b", r"\btapestry\b", r"\bcutting-edge\b", r"\bgroundbreaking\b",
        r"\bgame-chang(er|ing)\b", r"\ba testament to\b",
        r"\bIt'?s important to note\b", r"\bIn summary\b", r"\bIn conclusion\b",
        r"not just .{1,40}, (it'?s|but)\b",
    ],
    "ko": [
        r"다양한", r"폭넓은", r"혁신적", r"획기적", r"핵심적", r"효과적으로",
        r"완벽하게", r"손쉽게", r"경험을 선사", r"라고 할 수 있습니다",
        r"에 있어서", r"되어집니다", r"결론적으로", r"단순한 .{1,30}가 아니라",
        r"하는 것이 중요합니다",
    ],
    "ja": [
        r"と言えるでしょう", r"ではないでしょうか", r"と考えられます",
        r"と言っても過言ではありません", r"いかがでしたか", r"まとめると",
        r"単なる.{1,20}ではなく",
    ],
    "zh-Hans": [
        r"值得注意的是", r"综上所述", r"总的来说", r"不可否认", r"毫无疑问",
        r"赋能", r"闭环", r"底层逻辑", r"不只是.{1,20}，而是",
    ],
    "fr": [
        r"il est important de noter", r"En conclusion", r"En somme",
        r"\bcrucial(e|es|aux)?\b", r"\brévolutionnaire\b", r"il convient de",
        r"faire du sens", r"adresser un problème", r"Non seulement .{1,40}, mais",
    ],
    "de": [
        r"\bnahtlos\b", r"\btransformativ\b", r"\btiefgreifend\b", r"\bganzheitlich\b",
        r"\bwegweisend\b", r"\bSynergie\b", r"\bbahnbrechend\b",
        r"Es gilt zu beachten", r"Zusammenfassend lässt sich sagen",
        r"Nicht nur .{1,40}, sondern auch",
    ],
}

BOLD_LEAD_IN = re.compile(r"^\s*[-*] \*\*[^*]+:\*\*")
CODE_FENCE = re.compile(r"^```")


def body_lines(text: str):
    """Yield (lineno, line) outside fenced code blocks."""
    inside = False
    for lineno, line in enumerate(text.splitlines(), 1):
        if CODE_FENCE.match(line):
            inside = not inside
            continue
        if not inside:
            yield lineno, line


def check_phrasing(files: list[Path]) -> None:
    for path in files:
        if path.name == "AGENTS.md":
            continue  # the rule list itself quotes the banned phrases
        rel = path.relative_to(ROOT)
        lang = language_of(path)
        patterns = BANNED.get(lang, [])
        text = read(path)
        for lineno, line in body_lines(text):
            for pattern in patterns:
                if re.search(pattern, line):
                    fail(f"{rel}:{lineno}", f"machine-written phrasing: {pattern}")
            if BOLD_LEAD_IN.match(line):
                note(f"{rel}:{lineno}", "bullet uses the **Bold lead-in:** form")


KO_ENDING = re.compile(r"([가-힣]{1,5})\.")


def check_korean_rhythm(files: list[Path]) -> None:
    for path in files:
        if language_of(path) != "ko":
            continue
        rel = path.relative_to(ROOT)
        text = "\n".join(line for _, line in body_lines(read(path)))
        endings = KO_ENDING.findall(text)
        run, previous = 1, None
        for ending in endings:
            if ending == previous:
                run += 1
                if run == 4:
                    note(rel, f"'{ending}.' 로 끝나는 문장이 네 번 이어집니다")
            else:
                run = 1
            previous = ending


# --------------------------------------------------------------------------

def main() -> int:
    os.chdir(ROOT)
    facts = build_facts()
    files = markdown_files()

    check_release_facts(facts, files)
    check_parity()
    check_links(files)
    check_phrasing(files)
    check_korean_rhythm(files)

    for line in notes:
        print(f"note  {line}")
    for line in problems:
        print(f"FAIL  {line}")

    print()
    print(f"{len(files)} documents checked, {len(problems)} problems, {len(notes)} notes")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
