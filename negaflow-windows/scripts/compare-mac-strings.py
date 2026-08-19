# -*- coding: utf-8 -*-
"""Windows resw 의 모든 문구를 macOS Swift 표와 전수 대조한다.

  py scripts/compare-mac-strings.py            # 다른 것만 out/compare-mac-strings.txt 로
  py scripts/compare-mac-strings.py --apply    # macOS 값으로 덮어쓴다


resw 항목의 <comment> 에 원본 심볼(AppLocalizedText.x / AppLocalizedPhrase.x)이 적혀 있다.
그 심볼을 macOS 의 언어별 표에서 찾아 값이 같은지 본다. 다르면 macOS 값이 정답이다.

  py stringdiff.py            # 다른 것만 보고서 파일로 낸다
  py stringdiff.py --apply    # macOS 값으로 덮어쓴다
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# scripts/ 위가 negaflow-windows, 그 위가 저장소 뿌리입니다.
REPO = os.path.dirname(os.path.dirname(HERE)).replace(chr(92), "/")
REPORT_PATH = os.path.join(HERE, "..", "out", "compare-mac-strings.txt")
MAC = REPO + "/negaflow-mac/Sources/negaflowApp/Localization"
WIN = REPO + "/negaflow-windows/src/Shell/Strings"

os.makedirs(os.path.dirname(os.path.abspath(REPORT_PATH)), exist_ok=True)
REPORT = io.open(REPORT_PATH, "w", encoding="utf-8")


def report(line):
    REPORT.write(line + chr(10))


# OS 가 강제하는 차이만 예외입니다. 문구를 "다듬는" 예외는 없습니다.
EXCEPTIONS = {
    # macOS 파일 관리자 이름. Windows 에는 Finder 가 없습니다.
    "libraryShowInExplorer.Content": "Finder -> file explorer",
    # macOS 의 Option 키. Windows 자판에는 Alt 입니다.
    "developGrainMendCloneSourceHint.Text": "Option -> Alt",
    # macOS 는 %@, .NET 치환기는 {0} 입니다(LibraryWorkspaceCopy.cs:24).
    "namedFrameCopyDisplayFormat.Text": "%@ -> {0}",
    # ColorSync 는 macOS 전용 색 관리 이름입니다.
    "settingsColorSystemDisplayProfile.Text": "ColorSync product name dropped",
}

tables = {
    "en-US": "English",
    "ko-KR": "Korean",
    "ja-JP": "Japanese",
    "de-DE": "German",
    "fr-FR": "French",
    "zh-Hans": "SimplifiedChinese",
}


def swift_table(path):
    if not os.path.exists(path):
        return {}
    source = io.open(path, encoding="utf-8").read()
    values = {}
    pattern = re.compile(r'^\s*\.([A-Za-z0-9_]+)\s*:\s*"((?:\\.|[^"\\])*)"\s*,?\s*$', re.M)
    for match in pattern.finditer(source):
        key, raw = match.group(1), match.group(2)
        value = (raw.replace('\\"', '"').replace('\\n', chr(10))
                    .replace('\\t', chr(9)).replace('\\\\', chr(92)))
        values.setdefault(key, value)
    return values


mac = {}
for tag, table in tables.items():
    mac[tag] = {
        "AppLocalizedText": swift_table(
            MAC + "/Core/Tables/AppLocalizedText+%s.swift" % table),
        "AppLocalizedPhrase": swift_table(
            MAC + "/Phrases/Tables/AppLocalizedPhrase+%s.swift" % table),
    }

entry_pattern = re.compile(
    r'<data name="([A-Za-z0-9_]+)\.([A-Za-z]+)"[^>]*>\s*'
    r'<value>(.*?)</value>\s*'
    r'(?:<comment>(.*?)</comment>\s*)?</data>',
    re.S)


def unescape(value):
    return (value.replace("&lt;", "<").replace("&gt;", ">")
                 .replace("&quot;", '"').replace("&apos;", "'")
                 .replace("&amp;", "&"))


def escape(value):
    return value.replace("&", "&amp;").replace("<", "&lt;")


apply = "--apply" in sys.argv
total = 0
mismatched = 0
missing_symbol = 0
skipped = 0
changed_files = 0

for tag in tables:
    path = WIN + "/%s/Resources.resw" % tag
    raw = io.open(path, "rb").read()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig")
    newline = chr(13) + chr(10) if (chr(13) + chr(10)) in text else chr(10)
    edits = []
    for match in entry_pattern.finditer(text):
        key, prop, value, comment = match.groups()
        comment = (comment or "").strip()
        symbol = re.match(r"(AppLocalizedText|AppLocalizedPhrase)\.([A-Za-z0-9_]+)", comment)
        if not symbol:
            continue
        table, name = symbol.group(1), symbol.group(2)
        total += 1
        if key + "." + prop in EXCEPTIONS:
            skipped += 1
            continue
        expected = mac[tag][table].get(name)
        if expected is None:
            other = "AppLocalizedPhrase" if table == "AppLocalizedText" else "AppLocalizedText"
            expected = mac[tag][other].get(name)
        if expected is None:
            missing_symbol += 1
            report("[%s] %-40s symbol not found: %s.%s"
                   % (tag, key + "." + prop, table, name))
            continue
        actual = unescape(value).replace(chr(13) + chr(10), chr(10))
        if actual != expected:
            mismatched += 1
            report("[%s] %s" % (tag, key + "." + prop))
            report("    win: " + actual.replace(chr(10), "\\n"))
            report("    mac: " + expected.replace(chr(10), "\\n"))
            edits.append((match.start(3), match.end(3),
                          escape(expected).replace(chr(10), newline)))

    if apply and edits:
        for start, end, replacement in reversed(edits):
            text = text[:start] + replacement + text[end:]
        data = text.encode("utf-8")
        if bom:
            data = b"\xef\xbb\xbf" + data
        io.open(path, "wb").write(data)
        changed_files += 1

report("---")
REPORT.close()
print("compared %d - different %d - symbol-missing %d - os-forced %d%s"
      % (total, mismatched, missing_symbol, skipped,
         (" - files changed %d" % changed_files) if apply else ""))
