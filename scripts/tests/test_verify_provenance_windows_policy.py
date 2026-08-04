from __future__ import annotations

import importlib.util
import tempfile
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "verify_provenance",
    ROOT / "scripts/ci/verify-provenance.py",
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError("verify-provenance.py cannot be loaded")
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)


class WindowsProvenancePolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        (self.root / "Package.swift").write_text(
            "let package = Package(name: \"fixture\")\n",
            encoding="utf-8",
        )
        self.previous_root = VERIFIER.ROOT
        VERIFIER.ROOT = self.root

    def tearDown(self) -> None:
        VERIFIER.ROOT = self.previous_root
        self.temporary.cleanup()

    def make_file(self, relative: str, content: bytes = b"first-party\n") -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        return path

    def expect_policy_failure(self, path: Path) -> None:
        with redirect_stderr(StringIO()), self.assertRaises(SystemExit):
            VERIFIER.verify_tree_policy([path])

    def test_first_party_windows_native_roots_are_allowed(self) -> None:
        files = [
            self.make_file("Negaflow.Windows/src/Native/imaging/reference.cpp"),
            self.make_file("Negaflow.Windows/tests/Native.UnitTests/reference_tests.cpp"),
        ]
        self.assertEqual(VERIFIER.verify_tree_policy(files), (2, 0))

    def test_native_source_outside_windows_roots_is_rejected(self) -> None:
        self.expect_policy_failure(self.make_file("foreign/reference.cpp"))

    def test_vendor_directory_inside_windows_source_is_rejected(self) -> None:
        self.expect_policy_failure(
            self.make_file("Negaflow.Windows/src/vendor/reference.cpp")
        )

    def test_only_top_level_json_component_manifest_is_allowed(self) -> None:
        manifest = self.make_file(
            "Negaflow.Windows/third_party/manifest/components.json",
            b"{}\n",
        )
        self.assertEqual(VERIFIER.verify_tree_policy([manifest]), (1, 0))
        self.expect_policy_failure(
            self.make_file("Negaflow.Windows/third_party/payload.json", b"{}\n")
        )
        self.expect_policy_failure(
            self.make_file(
                "Negaflow.Windows/third_party/manifest/nested/payload.json",
                b"{}\n",
            )
        )


if __name__ == "__main__":
    unittest.main()
