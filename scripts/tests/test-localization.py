#!/usr/bin/env python3
"""Fixture tests for scripts/check-localization.py (E7-S7). Source rules and the
catalog rules only; the Xcode export itself is exercised by `make l10n-check`."""

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("check_localization", REPO / "scripts" / "check-localization.py")
check = importlib.util.module_from_spec(spec)
sys.modules["check_localization"] = check
spec.loader.exec_module(check)


class LocalizationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="LemmeTypeTests-l10n-")
        self.root = Path(self.tmp.name)
        (self.root / check.UI_SOURCES).mkdir(parents=True)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def source(self, text: str) -> list[str]:
        (self.root / check.UI_SOURCES / "View.swift").write_text(text, encoding="utf-8")
        return check.source_problems(self.root)

    def test_the_repository_sources_pass(self) -> None:
        self.assertEqual(check.source_problems(REPO), [])

    def test_a_bare_literal_is_flagged(self) -> None:
        for line in ['Text("Hello")', 'Button("Save") {}', 'Toggle("On", isOn: $on)', '.help("Tip")', 'Label("A", systemImage: "x")']:
            self.assertTrue(self.source(line), line)

    def test_module_bundle_and_verbatim_are_fine(self) -> None:
        for line in [
            'Text(String(localized: "Hello", bundle: .module))',
            'Text(verbatim: "·")',
            'Button(String(localized: "Save", bundle: .module)) {}',
            "Text(model.title)",
            '// Text("a comment is not code")',
        ]:
            self.assertEqual(self.source(line), [], line)

    def test_hand_formatting_is_flagged(self) -> None:
        for line in ['let s = String(format: "%.1f", x)', "let f = DateFormatter()", 'let size = "\\(n) MB"']:
            self.assertTrue(self.source(line), line)

    def write_catalog(self, strings: dict) -> Path:
        path = self.root / check.CATALOG
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"}), encoding="utf-8")
        return path

    def full_catalog(self) -> dict:
        return {key: {"comment": "A note for the translator"} for key in check.AMBIGUOUS}

    def test_a_complete_commented_catalog_passes(self) -> None:
        self.assertEqual(check.catalog_problems(self.write_catalog(self.full_catalog())), [])

    def test_a_missing_comment_is_flagged(self) -> None:
        strings = self.full_catalog()
        strings["Copy"] = {}
        self.assertIn("'Copy' is ambiguous and needs a translator comment", check.catalog_problems(self.write_catalog(strings)))

    def test_a_missing_entry_is_flagged(self) -> None:
        strings = self.full_catalog()
        del strings["Delete"]
        self.assertTrue(any("no 'Delete' entry" in p for p in check.catalog_problems(self.write_catalog(strings))))

    def test_a_stale_string_is_flagged(self) -> None:
        strings = self.full_catalog()
        strings["Old"] = {"extractionState": "stale"}
        self.assertTrue(any("'Old' is stale" in p for p in check.catalog_problems(self.write_catalog(strings))))

    def test_the_repository_catalog_is_checked_by_the_same_rules(self) -> None:
        self.assertIsInstance(check.catalog_problems(REPO / check.CATALOG), list)


if __name__ == "__main__":
    unittest.main(verbosity=2)
