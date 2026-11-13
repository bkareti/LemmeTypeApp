#!/usr/bin/env python3
"""Fixture tests for scripts/check-security-config.py (E6-S7).

Each test copies the files the check reads into a temporary tree, seeds one
violation, and expects the check to fail with a message about it.
"""

import importlib.util
import shutil
import sys
import plistlib
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
    "Config/LemmeTypeiOS.xcconfig",
    "App/LemmeTypeiOS/PrivacyInfo.xcprivacy",
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

    # The iPhone and iPad app (E8-S4, E8-S9).

    def test_the_iphone_app_may_not_declare_background_modes(self) -> None:
        self.append("Config/LemmeTypeiOS.xcconfig", "INFOPLIST_KEY_UIBackgroundModes = audio\n")
        self.assertIn("only audio is allowed", self.errors())

    def test_the_iphone_app_may_only_use_its_approved_entitlements_file(self) -> None:
        self.edit(
            "Config/LemmeTypeiOS.xcconfig", "App/LemmeTypeiOS/LemmeTypeiOS.entitlements",
            "App/LemmeTypeiOS/Other.entitlements",
        )  # fmt: skip
        self.assertIn("may only use", self.errors())
        (self.root / "App/LemmeTypeiOS/Other.entitlements").write_text(self.plist({}), encoding="utf-8")
        self.assertIn("Other.entitlements: not an approved", self.errors())

    def test_the_iphone_app_may_share_only_its_app_group(self) -> None:
        path = self.root / "App/LemmeTypeiOS/LemmeTypeiOS.entitlements"
        path.write_text(self.plist({"com.apple.security.application-groups": ["group.other"]}), encoding="utf-8")
        self.assertIn("only the App Group", self.errors())
        allowed = {"com.apple.security.application-groups": [check.IOS_APP_GROUP]}
        path.write_text(self.plist(allowed), encoding="utf-8")
        self.assertNotIn("only the App Group", self.errors())

    def test_the_iphone_app_may_only_use_the_audio_background_mode(self) -> None:
        path = self.root / "App/LemmeTypeiOS/Info.plist"
        path.write_text(self.plist({"UIBackgroundModes": ["audio", "location"]}), encoding="utf-8")
        self.assertIn("only the audio background mode", self.errors())
        path.write_text(self.plist({"UIBackgroundModes": ["audio"]}), encoding="utf-8")
        self.assertNotIn("only the audio background mode", self.errors())

    def test_the_keyboard_may_not_request_full_access(self) -> None:
        folder = self.root / "App/LemmeTypeKeyboard"
        folder.mkdir(parents=True)
        attributes = {"NSExtensionAttributes": {"RequestsOpenAccess": True}}
        (folder / "Info.plist").write_text(self.plist({"NSExtension": attributes}), encoding="utf-8")
        self.assertIn("must not request Full Access", self.errors())

    @staticmethod
    def plist(value: dict) -> str:
        return plistlib.dumps(value).decode("utf-8")

    def test_the_iphone_app_may_not_relax_app_transport_security(self) -> None:
        self.append("Config/LemmeTypeiOS.xcconfig", "INFOPLIST_KEY_NSAppTransportSecurity = NSAllowsArbitraryLoads\n")
        self.assertIn("App Transport Security", self.errors())

    def test_a_missing_privacy_manifest_fails(self) -> None:
        (self.root / "App/LemmeTypeiOS/PrivacyInfo.xcprivacy").unlink()
        self.assertIn("missing App/LemmeTypeiOS/PrivacyInfo.xcprivacy", self.errors())

    def test_the_privacy_manifest_may_not_declare_tracking(self) -> None:
        self.edit("App/LemmeTypeiOS/PrivacyInfo.xcprivacy", "<key>NSPrivacyTracking</key>\n\t<false/>", "<key>NSPrivacyTracking</key>\n\t<true/>")
        self.assertIn("NSPrivacyTracking must be false", self.errors())

    def test_the_privacy_manifest_declares_only_what_cloud_speech_and_the_subscription_send(self) -> None:
        self.assertEqual("", self.errors())  # the committed manifest declares the three allowed types

    def test_the_privacy_manifest_may_not_declare_another_data_type(self) -> None:
        self.edit("App/LemmeTypeiOS/PrivacyInfo.xcprivacy", "NSPrivacyCollectedDataTypeOtherUsageData", "NSPrivacyCollectedDataTypeLocation")  # fmt: skip
        self.assertIn("NSPrivacyCollectedDataTypeLocation is not a data type the paid launch collects", self.errors())

    def test_collected_data_may_not_be_used_for_advertising(self) -> None:
        self.edit("App/LemmeTypeiOS/PrivacyInfo.xcprivacy", "NSPrivacyCollectedDataTypePurposeAppFunctionality", "NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising")  # fmt: skip
        self.assertIn("app functionality only", self.errors())

    def test_an_api_that_needs_a_declared_reason_must_be_in_the_manifest(self) -> None:
        probe = self.root / "App/LemmeTypeiOS/Probe.swift"
        probe.write_text("import Foundation\nlet uptime = ProcessInfo.processInfo.systemUptime\n", encoding="utf-8")
        self.assertIn("NSPrivacyAccessedAPICategorySystemBootTime", self.errors())


if __name__ == "__main__":
    unittest.main(verbosity=2)
