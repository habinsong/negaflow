from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class CIGateTests(unittest.TestCase):
    def test_ci_runs_static_swift_and_gui_gates(self) -> None:
        gate = (ROOT / "scripts/ci-gate.sh").read_text(encoding="utf-8")
        self.assertIn("verify-static.sh", gate)
        self.assertIn("build-swift.sh", gate)
        self.assertIn("build-gui-tests.sh", gate)

    def test_swift_gate_enforces_complete_concurrency_as_errors(self) -> None:
        gate = (ROOT / "scripts/ci/check-swift-concurrency.sh").read_text(encoding="utf-8")
        self.assertIn("-strict-concurrency=complete", gate)
        self.assertIn("-warnings-as-errors", gate)
        self.assertIn("swift build", gate)
        self.assertIn("swift test", gate)

    def test_swift_gate_executes_real_cli_json_contract(self) -> None:
        gate = (ROOT / "scripts/ci/build-swift.sh").read_text(encoding="utf-8")
        verifier = (ROOT / "scripts/ci/verify-cli-json.py").read_text(encoding="utf-8")
        self.assertIn("verify-cli-json.py", gate)
        self.assertIn("capability field drift", verifier)
        self.assertIn("stdout must contain exactly one", verifier)

    def test_sane_boundary_is_an_explicit_gate(self) -> None:
        boundary = (ROOT / "scripts/ci/verify-boundaries.sh").read_text(encoding="utf-8")
        self.assertIn("SANE_" + "CONFIG_DIR", boundary)
        self.assertIn("scan" + "image", boundary)
        self.assertIn("negaflow-scanner-sane", boundary)
        self.assertIn("git grep", boundary)
        self.assertNotIn("if rg ", boundary)

    def test_static_gate_verifies_code_and_resource_provenance(self) -> None:
        gate = (ROOT / "scripts/ci/verify-static.sh").read_text(encoding="utf-8")
        verifier = (ROOT / "scripts/ci/verify-provenance.py").read_text(encoding="utf-8")
        self.assertIn("verify-provenance.py", gate)
        self.assertIn("bundled-resource-provenance-v1.json", verifier)
        self.assertIn("resource hash changed without provenance review", verifier)
        self.assertIn("\"sanei_\"", verifier)
        self.assertIn("\"negadoctor\"", verifier)

    def test_workflow_is_read_only_and_release_smoke_is_gated(self) -> None:
        workflow = (ROOT / ".github/workflows/ci.yml").read_text(encoding="utf-8")
        self.assertIn("contents: read", workflow)
        self.assertIn("runs-on: macos-26", workflow)
        self.assertIn("NEGAFLOW_CI_GUI: '1'", workflow)
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", workflow)
        self.assertIn("actions/upload-artifact@v7", workflow)

    def test_grainmend_workflow_uses_the_pinned_quality_sensitivity(self) -> None:
        workflow = (ROOT / ".github/workflows/defect-corpus.yml").read_text(encoding="utf-8")
        config = json.loads(
            (ROOT / "Config/defect-removal-film-r-v2-baseline.json").read_text(encoding="utf-8")
        )
        sensitivity = config["corpus"]["sensitivity"]
        self.assertIn(f"--sensitivity {sensitivity}", workflow)
        self.assertIn("build/defect-corpus/film-r-v2", workflow)


if __name__ == "__main__":
    unittest.main()
