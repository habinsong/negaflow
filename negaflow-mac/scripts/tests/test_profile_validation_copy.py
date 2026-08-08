from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]          # negaflow-mac
REPO_ROOT = Path(__file__).resolve().parents[3]     # README 는 저장소 루트
README_NAMES = (
    "README.md",
    "README_ko.md",
    "README_ja.md",
    "README_zh-Hans.md",
    "README_fr.md",
    "README_de.md",
)


class ProfileValidationCopyTests(unittest.TestCase):
    def test_readmes_explain_current_status_and_product_doc_defines_all_terms(self) -> None:
        for name in README_NAMES:
            body = (REPO_ROOT / name).read_text(encoding="utf-8")
            with self.subTest(readme=name):
                self.assertIn("realOnly", body)

        product_doc = (REPO_ROOT / "docs/product/FILM_PROFILES.md").read_text(encoding="utf-8")
        self.assertIn("realOnly", product_doc)
        self.assertIn("pairedSmoke", product_doc)
        self.assertIn("pairedValidated", product_doc)

    def test_removed_accuracy_claims_do_not_return(self) -> None:
        banned_claims = {
            "README.md": "profiles extracted from real scan pairs",
            "README_ko.md": "실제 스캔 쌍에서 뽑은 프로파일",
            "README_ja.md": "実際のスキャンペアから抽出したプロファイル",
            "README_zh-Hans.md": "从真实扫描对中提取的配置文件",
            "README_fr.md": "profils extraits de paires de scans réels",
            "README_de.md": "Profilen, die aus echten Scan-Paaren extrahiert wurden",
        }
        for name, claim in banned_claims.items():
            body = (REPO_ROOT / name).read_text(encoding="utf-8")
            with self.subTest(readme=name):
                self.assertNotIn(claim, body)

    def test_ui_localizes_status_and_cli_keeps_the_machine_readable_value(self) -> None:
        ui = (
            ROOT
            / "Sources/negaflowApp/Features/Develop/Inspector/BaseControlSection.swift"
        ).read_text(encoding="utf-8")
        cli = (
            ROOT / "Sources/negaflowCLI/Commands/CLI+DevelopCommand.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("validationStatus.displayName(language:", ui)
        self.assertIn("profile.validationStatus.rawValue", cli)


if __name__ == "__main__":
    unittest.main()
