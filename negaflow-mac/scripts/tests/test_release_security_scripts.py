from __future__ import annotations

import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class ReleaseSecurityScriptTests(unittest.TestCase):
    def test_ad_hoc_path_still_enables_hardened_runtime(self) -> None:
        with tempfile.TemporaryDirectory(prefix="negaflow-sign-test-") as raw:
            temporary = Path(raw)
            products = temporary / "Products"
            products.mkdir()
            chromabase_bundle = products / "negaflow_Chromabase.bundle"
            chromabase_bundle.mkdir()
            shutil.copytree(
                ROOT / "Sources/Chromabase/ScannerProfiles",
                chromabase_bundle / "ScannerProfiles",
            )
            app = temporary / "negaflow.app"
            subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts/package-app.sh"),
                    "/bin/echo",
                    str(products),
                    str(app),
                    "1.2.3",
                    "42",
                    "com.songhabin.negaflow.sign-tests",
                    "14.0",
                ],
                cwd=ROOT,
                check=True,
                capture_output=True,
            )
            subprocess.run(
                ["bash", str(ROOT / "scripts/sign-app.sh"), str(app), "-"],
                cwd=ROOT,
                check=True,
                capture_output=True,
            )
            details = subprocess.run(
                ["codesign", "-dv", "--verbose=4", str(app)],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("runtime", details.stderr)
            subprocess.run(
                ["codesign", "--verify", "--deep", "--strict", str(app)],
                check=True,
                capture_output=True,
            )

    def test_notarization_requires_keychain_profile_before_network(self) -> None:
        with tempfile.TemporaryDirectory(prefix="negaflow-notary-test-") as raw:
            temporary = Path(raw)
            archive = temporary / "negaflow.zip"
            archive.write_bytes(b"preflight")
            app = temporary / "negaflow.app"
            (app / "Contents").mkdir(parents=True)
            result = subprocess.run(
                [
                    "env",
                    "-u",
                    "NEGAFLOW_NOTARY_KEYCHAIN_PROFILE",
                    "bash",
                    str(ROOT / "scripts/notarize-app.sh"),
                    str(archive),
                    str(app),
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("NEGAFLOW_NOTARY_KEYCHAIN_PROFILE", result.stderr)

    def test_notarization_uses_current_apple_tools_and_least_privilege(self) -> None:
        notarize = (ROOT / "scripts/notarize-app.sh").read_text(encoding="utf-8")
        self.assertIn("notarytool submit", notarize)
        self.assertIn("stapler staple", notarize)
        self.assertIn("spctl --assess", notarize)
        self.assertIn("--type install", notarize)
        self.assertNotIn("altool", notarize)

        with (ROOT / "Config/negaflow.entitlements").open("rb") as stream:
            entitlements = plistlib.load(stream)
        self.assertEqual(entitlements, {})
        self.assertNotIn("com.apple.security.get-task-allow", entitlements)


if __name__ == "__main__":
    unittest.main()
