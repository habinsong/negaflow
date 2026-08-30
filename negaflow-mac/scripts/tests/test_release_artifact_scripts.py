from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]          # negaflow-mac
REPO_ROOT = Path(__file__).resolve().parents[3]     # 저장소 루트


class ReleaseArtifactScriptTests(unittest.TestCase):
    def test_artifact_script_covers_zip_pkg_dmg_dsym_uuid_and_checksums(self) -> None:
        body = (ROOT / "scripts/create-release-artifacts.sh").read_text(encoding="utf-8")

        self.assertIn("dwarfdump --uuid", body)
        self.assertIn("ditto -c -k", body)
        self.assertIn("hdiutil create", body)
        self.assertIn("pkgbuild", body)
        self.assertIn("PKG_NAME", body)
        self.assertIn("dSYM.zip", body)
        self.assertIn("write-release-checksums.sh", body)
        self.assertIn("sips -g hasAlpha", body)

    def test_checksum_script_writes_one_list_and_verifies_it(self) -> None:
        body = (ROOT / "scripts/write-release-checksums.sh").read_text(encoding="utf-8")

        self.assertIn("SHA256SUMS.txt", body)
        self.assertIn('shasum -a 256 "${FILES[@]}"', body)
        self.assertIn('shasum -a 256 -c "$CHECKSUM_NAME"', body)
        # 릴리스에 올리지 않는 파일은 목록에서 빠진다.
        self.assertIn("*.sha256|*.zip|*.exe|SHA256SUMS.txt", body)

    def test_distribution_mode_fails_before_build_without_credentials(self) -> None:
        environment = os.environ.copy()
        environment["NEGAFLOW_RELEASE_MODE"] = "distribution"
        environment.pop("NEGAFLOW_CODESIGN_IDENTITY", None)
        environment.pop("NEGAFLOW_NOTARY_KEYCHAIN_PROFILE", None)
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/build-release.sh")],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("NEGAFLOW_CODESIGN_IDENTITY", result.stderr)

    def test_distribution_mode_requires_installer_identity_before_build(self) -> None:
        environment = os.environ.copy()
        environment["NEGAFLOW_RELEASE_MODE"] = "distribution"
        environment["NEGAFLOW_CODESIGN_IDENTITY"] = "Developer ID Application: test"
        environment["NEGAFLOW_NOTARY_KEYCHAIN_PROFILE"] = "test"
        environment.pop("NEGAFLOW_INSTALLER_SIGN_IDENTITY", None)
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/build-release.sh")],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 2)
        self.assertIn("NEGAFLOW_INSTALLER_SIGN_IDENTITY", result.stderr)

    def test_release_orchestrator_keeps_local_and_distribution_paths_explicit(self) -> None:
        body = (ROOT / "scripts/build-release.sh").read_text(encoding="utf-8")

        self.assertIn("local", body)
        self.assertIn("distribution", body)
        self.assertIn("scripts/notarize-app.sh", body)
        self.assertIn("scripts/create-release-artifacts.sh", body)
        self.assertIn("negaflowApp.dSYM", body)
        self.assertEqual(body.count('bash "$ROOT/scripts/run-app.sh" build'), 1)
        self.assertIn('local architecture="universal"', body)
        self.assertIn('lipo "$source_executable" -thin arm64', body)
        self.assertIn('lipo "$source_dwarf" -thin arm64', body)
        self.assertIn("publish_variant arm64", body)
        self.assertIn("publish_variant universal", body)
        self.assertIn('"$final_dmg"', body)
        self.assertIn('"$final_pkg"', body)
        # 공증 스테이플로 dmg/pkg 가 바뀌므로 체크섬을 다시 적는다.
        self.assertIn("scripts/write-release-checksums.sh", body)

    def test_distribution_workflow_requires_signing_notarization_and_final_verification(self) -> None:
        body = (REPO_ROOT / ".github/workflows/distribution.yml").read_text(encoding="utf-8")

        self.assertIn("environment: distribution", body)
        self.assertIn("NEGAFLOW_DEVELOPER_ID_P12_BASE64", body)
        self.assertIn("NEGAFLOW_INSTALLER_ID_P12_BASE64", body)
        self.assertIn("NEGAFLOW_INSTALLER_SIGN_IDENTITY", body)
        self.assertIn("NEGAFLOW_NOTARY_PRIVATE_KEY_BASE64", body)
        self.assertIn("NEGAFLOW_RELEASE_MODE: distribution", body)
        self.assertIn("for app in build/release-apps/*/negaflow.app; do", body)
        self.assertIn('xcrun stapler validate "$app"', body)
        self.assertIn('spctl --assess --type execute --verbose=4 "$app"', body)
        self.assertIn(
            "for artifact in build/release-artifacts/*.dmg "
            "build/release-artifacts/*.pkg; do",
            body,
        )
        self.assertIn('xcrun stapler validate "$artifact"', body)
        self.assertNotIn("stapler validate build/negaflow.app", body)
        self.assertNotIn("NEGAFLOW_RELEASE_MODE: local", body)


if __name__ == "__main__":
    unittest.main()
