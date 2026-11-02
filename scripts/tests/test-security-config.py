#!/usr/bin/env python3
"""Fixture tests for scripts/check-security-config.py (E6-S7).

Each test copies the files the check reads into a temporary tree, seeds one
violation, and expects the check to fail with a message about it.
"""

import importlib.util
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("check_security_config", REPO / "scripts" / "check-security-config.py")
check = importlib.util.module_from_spec(spec)
sys.modules["check_security_config"] = check
spec.loader.exec_module(check)

FILES = [
    "App/LemmeType/LemmeType.entitlements",
    "Config/Base.xcconfig",
    "Config/Debug.xcconfig",
    "Config/LemmeType.xcconfig",
    "Config/Release.xcconfig",
    "Config/Version.xcconfig",
    "Packages/LemmeTypeKit/Package.swift",
    "project.yml",
    "docs/security/entitlements-allowlist.txt",
    "docs/security/usage-strings-allowlist.txt",
    "docs/security/dependencies-allowlist.txt",
]


class SecurityConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="LemmeTypeTests-security-")
        self.root = Path(self.tmp.name)
        for relative in FILES:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(REPO / relative, target)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def edit(self, relative: str, old: str, new: str) -> None:
        path = self.root / relative
        text = path.read_text(encoding="utf-8")
        self.assertIn(old, text, f"{relative} no longer contains the text this test edits")
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    def append(self, relative: str, text: str) -> None:
        path = self.root / relative
        path.write_text(path.read_text(encoding="utf-8") + text, encoding="utf-8")

    def errors(self) -> str:
        return "\n".join(check.run(self.root))

    def test_the_repository_passes(self) -> None:
        self.assertEqual(check.run(REPO), [])

    def test_a_new_entitlement_fails(self) -> None:
        self.edit(
            "App/LemmeType/LemmeType.entitlements",
            "</dict>",
            "\t<key>com.apple.security.network.client</key>\n\t<true/>\n</dict>",
        )
        self.assertIn("com.apple.security.network.client", self.errors())

    def test_get_task_allow_fails(self) -> None:
        self.edit(
            "App/LemmeType/LemmeType.entitlements",
            "</dict>",
            "\t<key>com.apple.security.get-task-allow</key>\n\t<true/>\n</dict>",
        )
        self.assertIn("get-task-allow", self.errors())

    def test_a_removed_entitlement_leaves_a_stale_allowlist_line(self) -> None:
        self.append("docs/security/entitlements-allowlist.txt", "com.apple.security.personal-information.location  # test\n")
        self.assertIn("no longer has", self.errors())

    def test_a_new_usage_string_fails(self) -> None:
        self.append("Config/LemmeType.xcconfig", "INFOPLIST_KEY_NSCameraUsageDescription = We use the camera.\n")
        self.assertIn("NSCameraUsageDescription", self.errors())

    def test_a_usage_string_in_the_project_spec_fails(self) -> None:
        self.append("project.yml", "# NSAppleEventsUsageDescription: tell other apps what to do\n")
        self.assertIn("NSAppleEventsUsageDescription", self.errors())

    def test_a_new_package_fails(self) -> None:
        self.edit(
            "Packages/LemmeTypeKit/Package.swift",
            "    targets: [",
            '    dependencies: [.package(url: "https://github.com/example/Widgets.git", from: "1.0.0")],\n    targets: [',
        )
        self.assertIn("package:Widgets", self.errors())

    def test_an_analytics_package_is_banned_by_name(self) -> None:
        self.edit(
            "Packages/LemmeTypeKit/Package.swift",
            "    targets: [",
            '    dependencies: [.package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "8.0.0")],\n    targets: [',
        )
        self.assertIn("not allowed", self.errors())

    def test_a_new_binary_target_fails(self) -> None:
        self.edit(
            "Packages/LemmeTypeKit/Package.swift",
            '        .target(name: "ModelAssets"',
            '        .binaryTarget(name: "extra", url: "https://example.com/extra.zip", checksum: "00"),\n        .target(name: "ModelAssets"',
        )
        self.assertIn("binaryTarget:extra", self.errors())

    def test_a_package_added_in_the_project_spec_fails(self) -> None:
        self.edit("project.yml", "packages:\n", "packages:\n  Widgets:\n    url: https://example.com/widgets\n    from: 1.0.0\n")
        self.assertIn("package:Widgets", self.errors())

    def test_turning_hardened_runtime_off_for_release_fails(self) -> None:
        self.edit("Config/Release.xcconfig", "ENABLE_HARDENED_RUNTIME = YES", "ENABLE_HARDENED_RUNTIME = NO")
        self.assertIn("ENABLE_HARDENED_RUNTIME", self.errors())

    def test_a_line_without_a_justification_fails(self) -> None:
        self.append("docs/security/entitlements-allowlist.txt", "com.apple.security.cs.disable-library-validation\n")
        self.assertIn("needs a justification", self.errors())

    def test_a_missing_allowlist_fails(self) -> None:
        (self.root / "docs/security/dependencies-allowlist.txt").unlink()
        self.assertIn("missing allowlist", self.errors())


if __name__ == "__main__":
    unittest.main(verbosity=2)
