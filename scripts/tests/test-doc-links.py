#!/usr/bin/env python3
"""Fixture tests for scripts/check-doc-links.py (E7-S9)."""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("check_doc_links", REPO / "scripts" / "check-doc-links.py")
check = importlib.util.module_from_spec(spec)
sys.modules["check_doc_links"] = check
spec.loader.exec_module(check)


class DocLinkTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="LemmeTypeTests-doclinks-")
        self.root = Path(self.tmp.name)
        (self.root / "docs/release").mkdir(parents=True)
        (self.root / "scripts").mkdir()
        (self.root / "scripts/real.sh").write_text("#!/bin/sh\n")
        (self.root / "Makefile").write_text("good-target: ## x\n\ttrue\n")
        (self.root / "docs/release/other.md").write_text("# other\n")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def doc(self, text: str) -> list[str]:
        (self.root / "README.md").write_text(text)
        return check.run(self.root)

    def test_the_repository_passes(self) -> None:
        self.assertEqual(check.run(REPO), [])

    def test_good_links_and_paths_pass(self) -> None:
        self.assertEqual(self.doc("See [other](docs/release/other.md#top), `scripts/real.sh`, and `make good-target`.\n"), [])

    def test_a_broken_link_fails(self) -> None:
        self.assertTrue(any("points at nothing" in e for e in self.doc("[x](docs/release/missing.md)\n")))

    def test_a_missing_path_fails(self) -> None:
        self.assertTrue(any("`scripts/gone.sh` does not exist" in e for e in self.doc("Run `scripts/gone.sh`.\n")))

    def test_a_missing_make_target_fails(self) -> None:
        self.assertTrue(any("not a Makefile target" in e for e in self.doc("Run `make nope`.\n")))

    def test_urls_anchors_placeholders_and_generated_paths_are_skipped(self) -> None:
        text = "[web](https://example.com/x) [top](#top) `build/release/LemmeType-X.Y.Z.zip` `docs/<name>.md` `scripts/*.sh`\n"
        self.assertEqual(self.doc(text), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
