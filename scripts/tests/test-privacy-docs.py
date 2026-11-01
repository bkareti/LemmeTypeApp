#!/usr/bin/env python3
"""Fixture tests for scripts/check-privacy-docs.py (E6-S8).

A small fake repository is built in a temporary folder so each test seeds one
kind of drift and expects the check to name it.
"""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("check_privacy_docs", REPO / "scripts" / "check-privacy-docs.py")
check = importlib.util.module_from_spec(spec)
sys.modules["check_privacy_docs"] = check
spec.loader.exec_module(check)

THREAT_HEADER = "| ID | Threat | Control | Verification | Residual risk |\n|---|---|---|---|---|\n"
GOOD_ROW = "| T-01 | Audio leaks | Nothing leaves | `NetworkTests`, `scripts/check.sh`, `make network-check`, `MA-1` | None known |\n"


class PrivacyDocsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="LemmeTypeTests-privacy-docs-")
        self.root = Path(self.tmp.name)
        self.write("Packages/LemmeTypeKit/Tests/AnyTests/NetworkTests.swift", "struct NetworkTests {}\n")
        self.write("scripts/check.sh", "#!/bin/sh\n")
        self.write("Makefile", "network-check: ## x\n\ttrue\n")
        self.write("docs/testing/manual-acceptance.md", "**MA-1 A step**\n1. do it\n")
        self.write("docs/security/threat-model.md", THREAT_HEADER + GOOD_ROW)
        self.write(
            "docs/security/privacy-release-checklist.md",
            "- [ ] Network is silent. — `make network-check`\n- [ ] A person read it. — `MA-1`\n",
        )

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write(self, relative: str, text: str) -> None:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def errors(self) -> str:
        return "\n".join(check.run(self.root))

    def test_the_repository_passes(self) -> None:
        self.assertEqual(check.run(REPO), [])

    def test_the_fixture_passes(self) -> None:
        self.assertEqual(check.run(self.root), [])

    def test_a_renamed_test_fails(self) -> None:
        (self.root / "Packages/LemmeTypeKit/Tests/AnyTests/NetworkTests.swift").write_text("struct Renamed {}\n")
        self.assertIn("`NetworkTests`, which does not exist", self.errors())

    def test_a_deleted_script_fails(self) -> None:
        (self.root / "scripts/check.sh").unlink()
        self.assertIn("`scripts/check.sh`, which does not exist", self.errors())

    def test_a_missing_make_target_fails(self) -> None:
        self.write("Makefile", "other: ## x\n\ttrue\n")
        self.assertIn("`make network-check`, which does not exist", self.errors())

    def test_a_missing_manual_step_fails(self) -> None:
        self.write("docs/testing/manual-acceptance.md", "**MA-2 Another**\n")
        self.assertIn("`MA-1`, which does not exist", self.errors())

    def test_a_threat_without_a_control_fails(self) -> None:
        self.write(
            "docs/security/threat-model.md",
            THREAT_HEADER + "| T-01 | Audio leaks | TBD | `NetworkTests` | None known |\n",
        )
        self.assertIn("T-01 has no control", self.errors())

    def test_a_threat_without_a_verification_fails(self) -> None:
        self.write(
            "docs/security/threat-model.md",
            THREAT_HEADER + "| T-01 | Audio leaks | Nothing leaves | We are careful | None known |\n",
        )
        self.assertIn("T-01 has no verification", self.errors())

    def test_a_threat_without_a_residual_risk_statement_fails(self) -> None:
        self.write(
            "docs/security/threat-model.md",
            THREAT_HEADER + "| T-01 | Audio leaks | Nothing leaves | `NetworkTests` | |\n",
        )
        self.assertIn("residual-risk", self.errors())

    def test_a_duplicate_id_fails(self) -> None:
        self.write("docs/security/threat-model.md", THREAT_HEADER + GOOD_ROW + GOOD_ROW)
        self.assertIn("T-01 appears twice", self.errors())

    def test_a_checklist_item_without_a_check_fails(self) -> None:
        self.write("docs/security/privacy-release-checklist.md", "- [ ] Trust us.\n")
        self.assertIn("cites nothing", self.errors())

    def test_a_checklist_item_citing_a_missing_check_fails(self) -> None:
        self.write("docs/security/privacy-release-checklist.md", "- [ ] Something. — `scripts/gone.sh`\n")
        self.assertIn("`scripts/gone.sh`, which does not exist", self.errors())

    def test_missing_documents_fail(self) -> None:
        (self.root / "docs/security/threat-model.md").unlink()
        self.assertIn("missing docs/security/threat-model.md", self.errors())


if __name__ == "__main__":
    unittest.main(verbosity=2)
