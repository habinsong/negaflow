from __future__ import annotations

import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LOCALES = ("en", "ko", "ja", "zh-Hans", "fr", "de")


class AppBundleMetadataTests(unittest.TestCase):
    def test_package_script_builds_complete_localized_app_bundle(self) -> None:
        with tempfile.TemporaryDirectory(prefix="negaflow-package-test-") as raw:
            temporary = Path(raw)
            products = temporary / "Products"
            products.mkdir()
            chromabase_bundle = products / "negaflow_Chromabase.bundle"
            chromabase_resources = chromabase_bundle / "Contents/Resources"
            chromabase_resources.mkdir(parents=True)
            shutil.copytree(
                ROOT / "Sources/Chromabase/ScannerProfiles",
                chromabase_resources / "ScannerProfiles",
            )
            (products / "negaflow_negaflowApp.bundle").mkdir()

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
                    "com.songhabin.negaflow.tests",
                    "14.0",
                ],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )

            with (app / "Contents/Info.plist").open("rb") as stream:
                metadata = plistlib.load(stream)

            self.assertEqual(metadata["CFBundleDisplayName"], "negaflow")
            self.assertEqual(metadata["CFBundleName"], "negaflow")
            self.assertEqual(metadata["CFBundleExecutable"], "negaflow")
            self.assertEqual(metadata["CFBundleIdentifier"], "com.songhabin.negaflow.tests")
            self.assertEqual(metadata["CFBundleShortVersionString"], "1.2.3")
            self.assertEqual(metadata["CFBundleVersion"], "42")
            self.assertEqual(metadata["CFBundleIconFile"], "AppIcon")
            self.assertEqual(
                metadata["LSApplicationCategoryType"],
                "public.app-category.photography",
            )
            self.assertEqual(metadata["LSMinimumSystemVersion"], "14.0")
            self.assertTrue(metadata["LSMultipleInstancesProhibited"])
            self.assertTrue(metadata["NSSupportsAutomaticGraphicsSwitching"])
            self.assertEqual(metadata["CFBundleLocalizations"], list(LOCALES))

            resources = app / "Contents/Resources"
            self.assertTrue((app / "Contents/MacOS/negaflow").is_file())
            self.assertGreater((resources / "AppIcon.icns").stat().st_size, 0)
            self.assertTrue((resources / "negaflow_Chromabase.bundle").is_dir())
            self.assertTrue((resources / "negaflow_negaflowApp.bundle").is_dir())
            packaged_profiles = (
                resources
                / "negaflow_Chromabase.bundle/Contents/Resources/ScannerProfiles"
            )
            self.assertGreater((packaged_profiles / "manifest.json").stat().st_size, 0)
            expected_profile_names = {
                path.name
                for path in (ROOT / "Sources/Chromabase/ScannerProfiles").glob("*.json")
                if path.name != "manifest.json"
            }
            self.assertTrue(expected_profile_names)
            self.assertEqual(
                expected_profile_names,
                {
                    path.name
                    for path in packaged_profiles.glob("*.json")
                    if path.name != "manifest.json"
                },
            )
            for locale in LOCALES:
                with self.subTest(locale=locale):
                    self.assertGreater(
                        (resources / f"{locale}.lproj/InfoPlist.strings").stat().st_size,
                        0,
                    )

    def test_package_script_rejects_empty_chromabase_resource_bundle(self) -> None:
        with tempfile.TemporaryDirectory(prefix="negaflow-package-test-") as raw:
            temporary = Path(raw)
            products = temporary / "Products"
            (products / "negaflow_Chromabase.bundle").mkdir(parents=True)

            result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts/package-app.sh"),
                    "/bin/echo",
                    str(products),
                    str(temporary / "negaflow.app"),
                    "1.2.3",
                    "42",
                    "com.songhabin.negaflow.tests",
                    "14.0",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("ScannerProfiles manifest", result.stderr)

    def test_package_script_rejects_missing_declared_scanner_profile(self) -> None:
        with tempfile.TemporaryDirectory(prefix="negaflow-package-test-") as raw:
            temporary = Path(raw)
            products = temporary / "Products"
            chromabase_bundle = products / "negaflow_Chromabase.bundle"
            chromabase_bundle.mkdir(parents=True)
            shutil.copytree(
                ROOT / "Sources/Chromabase/ScannerProfiles",
                chromabase_bundle / "ScannerProfiles",
            )
            missing_profile = next(
                path
                for path in (chromabase_bundle / "ScannerProfiles").glob("*.json")
                if path.name != "manifest.json"
            )
            missing_profile.unlink()

            result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts/package-app.sh"),
                    "/bin/echo",
                    str(products),
                    str(temporary / "negaflow.app"),
                    "1.2.3",
                    "42",
                    "com.songhabin.negaflow.tests",
                    "14.0",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("ScannerProfiles profile", result.stderr)
            self.assertIn(missing_profile.name, result.stderr)

    def test_package_script_rejects_tampered_scanner_profile_bytes(self) -> None:
        with tempfile.TemporaryDirectory(prefix="negaflow-package-test-") as raw:
            temporary = Path(raw)
            products = temporary / "Products"
            chromabase_bundle = products / "negaflow_Chromabase.bundle"
            chromabase_bundle.mkdir(parents=True)
            shutil.copytree(
                ROOT / "Sources/Chromabase/ScannerProfiles",
                chromabase_bundle / "ScannerProfiles",
            )
            tampered_profile = next(
                path
                for path in (chromabase_bundle / "ScannerProfiles").glob("*.json")
                if path.name != "manifest.json"
            )
            tampered_profile.write_bytes(tampered_profile.read_bytes() + b"\n")

            result = subprocess.run(
                [
                    "bash",
                    str(ROOT / "scripts/package-app.sh"),
                    "/bin/echo",
                    str(products),
                    str(temporary / "negaflow.app"),
                    "1.2.3",
                    "42",
                    "com.songhabin.negaflow.tests",
                    "14.0",
                ],
                cwd=ROOT,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("fileSHA256", result.stderr)
            self.assertIn(tampered_profile.name, result.stderr)

    def test_product_version_and_build_sources_are_valid(self) -> None:
        version = (ROOT / "Sources/Chromabase/ProductVersion.txt").read_text().strip()
        build = (ROOT / "Sources/Chromabase/ProductBuild.txt").read_text().strip()

        self.assertRegex(version, r"^[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z.-]+)?$")
        self.assertRegex(build, r"^[1-9][0-9]*$")


if __name__ == "__main__":
    unittest.main()
