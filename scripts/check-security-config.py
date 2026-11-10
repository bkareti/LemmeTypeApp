#!/usr/bin/env python3
"""Security configuration check (E6-S7, ADR 0025).

Fails when the app gains an entitlement, a privacy usage string, or a
dependency that is not in the reviewed allowlists under docs/security/, when
Hardened Runtime is off for Release, or when an analytics or crash-reporting
package appears. Every allowlist line needs a justification, and a line whose
subject no longer exists must be removed, so a permission cannot linger.

    scripts/check-security-config.py [--root <repository root>]
"""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path

ENTITLEMENTS = "App/LemmeType/LemmeType.entitlements"
CONFIG_DIR = "Config"
RELEASE_CONFIG = "Config/Release.xcconfig"
PACKAGE_MANIFEST = "Packages/LemmeTypeKit/Package.swift"
PROJECT_SPEC = "project.yml"
IOS_CONFIG = "Config/LemmeTypeiOS.xcconfig"
IOS_APP_DIR = "App/LemmeTypeiOS"
IOS_PRIVACY_MANIFEST = "App/LemmeTypeiOS/PrivacyInfo.xcprivacy"
IOS_ENTITLEMENTS = "App/LemmeTypeiOS/LemmeTypeiOS.entitlements"
IOS_INFO_PLIST = "App/LemmeTypeiOS/Info.plist"
KEYBOARD_INFO_PLIST = "App/LemmeTypeKeyboard/Info.plist"
IOS_ENTITLEMENT_FILES = (IOS_ENTITLEMENTS, "App/LemmeTypeKeyboard/LemmeTypeKeyboard.entitlements")
IOS_APP_GROUP = "group.com.lemmetype.LemmeType"
SOURCE_DIRS = ("Packages/LemmeTypeKit/Sources", "App")

# Required-reason APIs (Apple's privacy manifest rules): the source tokens that
# use them, and the manifest category that must declare them.
REQUIRED_REASON_APIS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b",
    "NSPrivacyAccessedAPICategoryDiskSpace": r"volumeAvailableCapacity|systemFreeSize|NSFileSystemFreeSize|volumeTotalCapacity",
    "NSPrivacyAccessedAPICategoryFileTimestamp": r"creationDate|modificationDate|contentModificationDate|fileModificationDate|getattrlist|\bf?stat\(",
    "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time|mach_continuous_time|clock_gettime_nsec_np",
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
}  # fmt: skip

# Packages that collect usage or crash data. Banned by name, whatever the allowlist says.
BANNED_NAMES = (
    "sentry", "firebase", "crashlytics", "mixpanel", "amplitude", "segment", "appcenter", "bugsnag",
    "posthog", "datadog", "telemetrydeck", "countly", "flurry", "appsflyer", "adjust", "heap",
    "newrelic", "instabug", "raygun", "rollbar", "logrocket", "plausible", "matomo", "analytics",
    "telemetry", "crashreport",
)  # fmt: skip

MIN_JUSTIFICATION = 10


class Report:
    def __init__(self) -> None:
        self.errors: list[str] = []

    def error(self, message: str) -> None:
        self.errors.append(message)


def read_allowlist(path: Path, report: Report) -> dict[str, str]:
    """`subject  # justification` lines. Subjects without a justification are errors."""
    if not path.is_file():
        report.error(f"missing allowlist: {path.name}")
        return {}
    subjects: dict[str, str] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        subject, _, why = line.partition("#")
        subject, why = subject.strip(), why.strip()
        if len(why) < MIN_JUSTIFICATION:
            report.error(f"{path.name}:{number}: '{subject}' needs a justification after '#'")
        subjects[subject] = why
    return subjects


def check_entitlements(root: Path, allowed: dict[str, str], report: Report) -> None:
    path = root / ENTITLEMENTS
    if not path.is_file():
        report.error(f"missing {ENTITLEMENTS}")
        return
    with path.open("rb") as handle:
        present = set(plistlib.load(handle))
    for key in sorted(present - set(allowed)):
        report.error(f"entitlement not in docs/security/entitlements-allowlist.txt: {key}")
    for key in sorted(set(allowed) - present):
        report.error(f"entitlements allowlist names '{key}', which the app no longer has: remove the line")


def usage_keys(root: Path) -> set[str]:
    found: set[str] = set()
    for config in sorted((root / CONFIG_DIR).glob("*.xcconfig")):
        found |= set(re.findall(r"INFOPLIST_KEY_(NS\w+UsageDescription)\b", config.read_text(encoding="utf-8")))
    spec = root / PROJECT_SPEC
    if spec.is_file():
        found |= set(re.findall(r"\b(NS\w+UsageDescription)\b", spec.read_text(encoding="utf-8")))
    for plist in sorted((root / "App").rglob("*.plist")):
        try:
            with plist.open("rb") as handle:
                found |= {key for key in plistlib.load(handle) if re.fullmatch(r"NS\w+UsageDescription", key)}
        except (plistlib.InvalidFileException, ValueError):
            continue
    return found


def check_usage_strings(root: Path, allowed: dict[str, str], report: Report) -> None:
    present = usage_keys(root)
    for key in sorted(present - set(allowed)):
        report.error(f"usage description not in docs/security/usage-strings-allowlist.txt: {key}")
    for key in sorted(set(allowed) - present):
        report.error(f"usage-string allowlist names '{key}', which the app no longer declares: remove the line")


def package_subjects(root: Path) -> set[str]:
    """`package:<name>` for remote packages and `binaryTarget:<name>` for binaries."""
    subjects: set[str] = set()
    manifest = root / PACKAGE_MANIFEST
    if manifest.is_file():
        text = manifest.read_text(encoding="utf-8")
        # Drop comments but keep the `//` inside URLs such as https://github.com/...
        text = re.sub(r"(?<![:\w\"])//[^\n]*", "", text)
        for url in re.findall(r"\.package\(\s*url:\s*\"([^\"]+)\"", text):
            subjects.add("package:" + re.sub(r"\.git$", "", url.rstrip("/").rsplit("/", 1)[-1]))
        for name in re.findall(r"\.binaryTarget\(\s*name:\s*\"([^\"]+)\"", text):
            subjects.add(f"binaryTarget:{name}")
    spec = root / PROJECT_SPEC
    if spec.is_file():
        in_packages = False
        for line in spec.read_text(encoding="utf-8").splitlines():
            if re.match(r"^packages:\s*$", line):
                in_packages = True
                continue
            if in_packages and re.match(r"^\S", line):
                in_packages = False
            match = re.match(r"^  (\w[\w.-]*):\s*$", line)
            if in_packages and match and match.group(1) != "LemmeTypeKit":
                subjects.add(f"package:{match.group(1)}")
    return subjects


def check_dependencies(root: Path, allowed: dict[str, str], report: Report) -> None:
    present = package_subjects(root)
    for subject in sorted(present):
        lowered = subject.lower()
        for banned in BANNED_NAMES:
            if banned in lowered:
                report.error(f"{subject}: analytics, telemetry, or crash-reporting code is not allowed (ADR 0025)")
                break
        else:
            if subject not in allowed:
                report.error(f"dependency not in docs/security/dependencies-allowlist.txt: {subject}")
    for subject in sorted(set(allowed) - present):
        report.error(f"dependency allowlist names '{subject}', which is no longer used: remove the line")


def check_hardened_runtime(root: Path, report: Report) -> None:
    path = root / RELEASE_CONFIG
    if not path.is_file():
        report.error(f"missing {RELEASE_CONFIG}")
        return
    text = path.read_text(encoding="utf-8")
    settings = re.findall(r"^\s*ENABLE_HARDENED_RUNTIME\s*=\s*(\S+)", text, re.MULTILINE)
    if not settings or settings[-1] != "YES":
        report.error(f"{RELEASE_CONFIG}: ENABLE_HARDENED_RUNTIME must be YES for Release")
    if re.search(r"^\s*ENABLE_APP_SANDBOX\s*=", text, re.MULTILINE):
        report.error(f"{RELEASE_CONFIG}: the App Sandbox setting changes the platform baseline (ADR 0001)")


def check_ios_extension_entitlements(root: Path, report: Report) -> None:
    """The app and its keyboard share one App Group and nothing else (ADR 0032)."""
    for folder in ("App/LemmeTypeiOS", "App/LemmeTypeKeyboard", "App/LemmeTypeiOSWidgets", "App/LemmeTypeiOSShared"):
        for path in sorted((root / folder).rglob("*.entitlements")) if (root / folder).is_dir() else []:
            relative = path.relative_to(root).as_posix()
            if relative not in IOS_ENTITLEMENT_FILES:
                report.error(f"{relative}: not an approved iPhone entitlements file; adding one needs a new ADR")
                continue
            with path.open("rb") as handle:
                data = plistlib.load(handle)
            if data != {"com.apple.security.application-groups": [IOS_APP_GROUP]}:
                report.error(f"{relative}: only the App Group {IOS_APP_GROUP} is allowed (ADR 0032)")


def check_ios_background_modes(root: Path, report: Report) -> None:
    path = root / IOS_INFO_PLIST
    if not path.is_file():
        return
    with path.open("rb") as handle:
        modes = plistlib.load(handle).get("UIBackgroundModes", [])
    if set(modes) - {"audio"}:
        report.error(f"{IOS_INFO_PLIST}: only the audio background mode is allowed (ADR 0032)")


def check_keyboard_open_access(root: Path, report: Report) -> None:
    path = root / KEYBOARD_INFO_PLIST
    if not path.is_file():
        return
    with path.open("rb") as handle:
        attributes = plistlib.load(handle).get("NSExtension", {}).get("NSExtensionAttributes", {})
    if attributes.get("RequestsOpenAccess") is not False:
        report.error(f"{KEYBOARD_INFO_PLIST}: the keyboard must not request Full Access (ADR 0032)")


def check_ios_target(root: Path, report: Report) -> None:
    """The iPhone and iPad app has only the App Group entitlement and the audio
    background mode that Action Button dictation needs (ADR 0032), a keyboard that
    never asks for Full Access, no ATS exceptions, and a privacy manifest that
    matches the code (E8-S4, E8-S9, ADR 0027)."""
    config = root / IOS_CONFIG
    if not config.is_file():
        return  # no iOS target in this tree
    text = config.read_text(encoding="utf-8")
    if re.search(r"INFOPLIST_KEY_UIBackgroundModes", text):
        report.error(f"{IOS_CONFIG}: background modes belong in {IOS_INFO_PLIST}, where only audio is allowed (ADR 0032)")
    signed = re.search(r"^\s*CODE_SIGN_ENTITLEMENTS\s*=\s*(\S+)", text, re.MULTILINE)
    if signed and signed.group(1) != IOS_ENTITLEMENTS:
        report.error(f"{IOS_CONFIG}: the iPhone app may only use {IOS_ENTITLEMENTS}; another one needs a new ADR")
    check_ios_extension_entitlements(root, report)
    check_ios_background_modes(root, report)
    check_keyboard_open_access(root, report)
    app_dir = root / IOS_APP_DIR
    plist_text = text + "".join(p.read_text(encoding="utf-8", errors="ignore") for p in sorted(app_dir.rglob("*.plist")))
    if re.search(r"NSAppTransportSecurity|NSAllowsArbitraryLoads", plist_text):
        report.error("the iPhone app must not relax App Transport Security: its only download is HTTPS")

    manifest = root / IOS_PRIVACY_MANIFEST
    if not manifest.is_file():
        report.error(f"missing {IOS_PRIVACY_MANIFEST}")
        return
    with manifest.open("rb") as handle:
        data = plistlib.load(handle)
    if data.get("NSPrivacyTracking") is not False:
        report.error(f"{IOS_PRIVACY_MANIFEST}: NSPrivacyTracking must be false")
    if data.get("NSPrivacyTrackingDomains"):
        report.error(f"{IOS_PRIVACY_MANIFEST}: the app contacts no tracking domains")
    if data.get("NSPrivacyCollectedDataTypes"):
        report.error(f"{IOS_PRIVACY_MANIFEST}: the app collects no data; nothing leaves the device")
    declared = {item.get("NSPrivacyAccessedAPIType") for item in data.get("NSPrivacyAccessedAPITypes", [])}
    sources = "".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for folder in SOURCE_DIRS for path in sorted((root / folder).rglob("*.swift"))
        if "Tests" not in path.parts and "LemmeTypeiOSUITests" not in path.parts
    )  # fmt: skip
    for category, pattern in REQUIRED_REASON_APIS.items():
        if re.search(pattern, sources) and category not in declared:
            report.error(f"{IOS_PRIVACY_MANIFEST}: the code uses an API that needs {category}, which is not declared")


def run(root: Path) -> list[str]:
    report = Report()
    security = root / "docs" / "security"
    check_entitlements(root, read_allowlist(security / "entitlements-allowlist.txt", report), report)
    check_usage_strings(root, read_allowlist(security / "usage-strings-allowlist.txt", report), report)
    check_dependencies(root, read_allowlist(security / "dependencies-allowlist.txt", report), report)
    check_hardened_runtime(root, report)
    check_ios_target(root, report)
    return report.errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    errors = run(parser.parse_args().root.resolve())
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        print("See docs/decisions/0025-privacy-data-and-history.md.", file=sys.stderr)
        return 1
    print("Entitlements, usage strings, dependencies, and Hardened Runtime match the reviewed allowlists.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
