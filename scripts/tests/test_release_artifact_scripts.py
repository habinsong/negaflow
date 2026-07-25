from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ReleaseArtifactScriptTests(unittest.TestCase):
    def test_artifact_script_covers_zip_pkg_dmg_dsym_uuid_and_checksums(self) -> None:
        body = (ROOT / "scripts/create-release-artifacts.sh").read_text(encoding="utf-8")

        self.assertIn("dwarfdump --uuid", body)
        self.assertIn("ditto -c -k", body)
        self.assertIn("hdiutil create", body)
        self.assertIn("pkgbuild", body)
        self.assertIn("PKG_NAME", body)
        self.assertIn("dSYM.zip", body)
        self.assertIn("shasum -a 256", body)
        self.assertIn("sips -g hasAlpha", body)

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
        self.assertIn("build_variant arm64", body)
        self.assertIn("build_variant universal", body)
        self.assertIn('"$final_dmg"', body)
        self.assertIn('"$final_pkg"', body)
        self.assertIn("shasum -a 256 -c", body)

    def test_distribution_workflow_requires_signing_notarization_and_final_verification(self) -> None:
        body = (ROOT / ".github/workflows/distribution.yml").read_text(encoding="utf-8")

        self.assertIn("environment: distribution", body)
        self.assertIn("NEGAFLOW_DEVELOPER_ID_P12_BASE64", body)
        self.assertIn("NEGAFLOW_INSTALLER_ID_P12_BASE64", body)
        self.assertIn("NEGAFLOW_INSTALLER_SIGN_IDENTITY", body)
        self.assertIn("NEGAFLOW_NOTARY_PRIVATE_KEY_BASE64", body)
        self.assertIn("NEGAFLOW_RELEASE_MODE: distribution", body)
        self.assertIn("for app in build/release-apps/*/Negaflow.app; do", body)
        self.assertIn('xcrun stapler validate "$app"', body)
        self.assertIn('spctl --assess --type execute --verbose=4 "$app"', body)
        self.assertIn(
            "for artifact in build/release-artifacts/*.dmg "
            "build/release-artifacts/*.pkg; do",
            body,
        )
        self.assertIn('xcrun stapler validate "$artifact"', body)
        self.assertNotIn("stapler validate build/Negaflow.app", body)
        self.assertNotIn("NEGAFLOW_RELEASE_MODE: local", body)


if __name__ == "__main__":
    unittest.main()
