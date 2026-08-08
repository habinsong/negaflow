from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path


# 문서·README 는 플랫폼 트리 밖 저장소 루트에 있다.
ROOT = Path(__file__).resolve().parents[3]
READMES = (
    "README.md",
    "README_ko.md",
    "README_ja.md",
    "README_zh-Hans.md",
    "README_fr.md",
    "README_de.md",
)
# English is the default and lives at the top of docs/. Every other language is a
# sibling folder holding the same set of documents.
TRANSLATIONS = ("ko", "ja", "zh-Hans", "fr", "de")
DOCS_HOME_LINKS = {
    "": "[Docs home](../README.md)",
    "ko": "[문서 홈](../README.md)",
    "ja": "[ドキュメントホーム](../README.md)",
    "zh-Hans": "[文档首页](../README.md)",
    "fr": "[Accueil de la documentation](../README.md)",
    "de": "[Dokumentationsstart](../README.md)",
}
README_LANGUAGES = {
    "README.md": "",
    "README_ko.md": "ko",
    "README_ja.md": "ja",
    "README_zh-Hans.md": "zh-Hans",
    "README_fr.md": "fr",
    "README_de.md": "de",
}
CANONICAL_PRODUCT_DOCS = (
    "product/PROJECT_STATUS.md",
    "product/CHROMA_ENGINE.md",
    "product/GRAINMEND.md",
    "product/FILM_PROFILES.md",
    "architecture/PRODUCT_ARCHITECTURE.md",
    "validation/REAL_QA_CHECKLIST.md",
)


def docs_root(language: str) -> Path:
    return ROOT / "docs" / language if language else ROOT / "docs"


def documents_in(language: str) -> list[Path]:
    base = docs_root(language)
    found = []
    for document in sorted(base.rglob("*.md")):
        if not language and document.relative_to(base).parts[0] in TRANSLATIONS:
            continue
        found.append(document)
    return found


class DocumentationStateTests(unittest.TestCase):
    def test_local_markdown_links_resolve_in_a_clean_checkout(self) -> None:
        documents = sorted(ROOT.glob("*.md")) + sorted((ROOT / "docs").rglob("*.md"))
        markdown_link_pattern = re.compile(r"\[[^\]]+\]\(([^)#]+)(?:#[^)]+)?\)")
        html_link_pattern = re.compile(r'(?:href|src)="([^"#]+)(?:#[^"]*)?"')
        missing: list[str] = []
        ignored: list[str] = []

        for document in documents:
            text = document.read_text(encoding="utf-8")
            targets = markdown_link_pattern.findall(text) + html_link_pattern.findall(text)
            for target in targets:
                if "://" in target or target.startswith("mailto:"):
                    continue
                resolved = (document.parent / target).resolve()
                if not resolved.exists():
                    missing.append(f"{document.relative_to(ROOT)} -> {target}")
                    continue
                result = subprocess.run(
                    ["git", "check-ignore", "-q", str(resolved)],
                    cwd=ROOT,
                    check=False,
                )
                if result.returncode == 0:
                    ignored.append(f"{document.relative_to(ROOT)} -> {target}")

        self.assertEqual(missing, [], f"missing local documentation links: {missing}")
        self.assertEqual(ignored, [], f"ignored local documentation links: {ignored}")

    def test_docs_index_lists_every_markdown_document(self) -> None:
        for language in ("", *TRANSLATIONS):
            base = docs_root(language)
            index = (base / "README.md").read_text(encoding="utf-8")
            for document in documents_in(language):
                if document.name == "README.md":
                    continue
                relative = document.relative_to(base).as_posix()
                with self.subTest(language=language or "en", document=relative):
                    text = document.read_text(encoding="utf-8")
                    self.assertIn(f"({relative})", index)
                    self.assertIn(DOCS_HOME_LINKS[language], text)

    def test_every_language_carries_the_same_documents(self) -> None:
        english = {
            document.relative_to(docs_root("")).as_posix()
            for document in documents_in("")
        }
        for language in TRANSLATIONS:
            translated = {
                document.relative_to(docs_root(language)).as_posix()
                for document in documents_in(language)
            }
            with self.subTest(language=language):
                self.assertEqual(translated, english)

    def test_docs_use_balanced_supported_markdown_blocks(self) -> None:
        for document in sorted((ROOT / "docs").rglob("*.md")):
            text = document.read_text(encoding="utf-8")
            with self.subTest(document=document.relative_to(ROOT).as_posix()):
                self.assertEqual(text.count("```") % 2, 0)
                self.assertEqual(text.count("<details"), text.count("</details>"))
                self.assertNotIn("```text", text)
                self.assertNotRegex(text, r"[├└│▼]")

    def test_every_readme_links_the_canonical_product_docs(self) -> None:
        for name, language in README_LANGUAGES.items():
            prefix = f"docs/{language}/" if language else "docs/"
            with self.subTest(name=name):
                text = (ROOT / name).read_text(encoding="utf-8")
                for document in CANONICAL_PRODUCT_DOCS:
                    self.assertIn(prefix + document, text)

    def test_localized_readmes_keep_the_korean_structure_and_commands(self) -> None:
        def structure(text: str) -> tuple[list[int], int, list[str]]:
            heading_levels = [
                len(match.group(1))
                for match in re.finditer(r"^(#{2,6})\s", text, flags=re.MULTILINE)
            ]
            table_rows = sum(1 for line in text.splitlines() if line.startswith("|"))
            bash_commands: list[str] = []
            for block in re.findall(r"```bash\n(.*?)```", text, flags=re.DOTALL):
                bash_commands.extend(
                    line.strip()
                    for line in block.splitlines()
                    if line.strip() and not line.lstrip().startswith("#")
                )
            return heading_levels, table_rows, bash_commands

        korean = structure((ROOT / "README_ko.md").read_text(encoding="utf-8"))
        for name in READMES:
            with self.subTest(name=name):
                text = (ROOT / name).read_text(encoding="utf-8")
                self.assertEqual(structure(text), korean)
                for token in (
                    "GrainMend",
                    "Chromabase",
                    "realOnly",
                    "Digital ICE",
                    "iSRD",
                    "SRDx",
                    "928",
                    "Apache",
                ):
                    self.assertIn(token, text)

    def test_status_describes_sqlite_primary_and_json_interchange_boundary(self) -> None:
        # Korean is the source the other languages are written from, so the wording
        # of the storage boundary is pinned there.
        status = (ROOT / "docs/ko/product/PROJECT_STATUS.md").read_text(encoding="utf-8")
        self.assertIn("기본 저장소는 `library.sqlite`", status)
        self.assertIn("백업·아카이브 교환 형식", status)
        self.assertIn("증거가 맞지 않으면 닫힌 상태로 실패", status)
        self.assertIn("bash scripts/ci-gate.sh", status)
        self.assertIn("bash scripts/build-release.sh", status)
        self.assertIn("Apple Silicon(`arm64`)과 Universal(`arm64`, `x86_64`)", status)
        self.assertIn("ZIP, PKG, DMG, dSYM", status)
        self.assertIn("CLI_JSON.md", status)
        self.assertIn("REAL_QA_CHECKLIST.md", status)

    def test_main_docs_do_not_own_plugin_runtime_instructions(self) -> None:
        texts = [
            (ROOT / name).read_text(encoding="utf-8")
            for name in READMES
        ]
        for language in ("", *TRANSLATIONS):
            plugins = docs_root(language) / "architecture/SCANNER_PLUGINS.md"
            texts.append(plugins.read_text(encoding="utf-8"))
        combined = "\n".join(texts)
        self.assertNotIn("brew install " + "sane-" + "backends", combined)
        self.assertNotIn("scan" + "image -L", combined)
        self.assertNotIn("scan" + "image -A", combined)
        self.assertIn("negaflow-scanner-sane", combined)

    def test_real_qa_owns_manual_evidence_and_blocking_rules(self) -> None:
        qa = (ROOT / "docs/ko/validation/REAL_QA_CHECKLIST.md").read_text(encoding="utf-8")
        self.assertIn("최종 화면 확인과 실제 장비 확인은 사용자가", qa)
        self.assertIn("실제 스캐너", qa)
        self.assertIn("자동 `REJECT`", qa)
        self.assertIn("CLI `detect --json`", qa)
        self.assertIn("7200 DPI", qa)


if __name__ == "__main__":
    unittest.main()
