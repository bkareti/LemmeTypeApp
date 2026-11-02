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


def run(root: Path) -> list[str]:
    report = Report()
    security = root / "docs" / "security"
    check_entitlements(root, read_allowlist(security / "entitlements-allowlist.txt", report), report)
    check_usage_strings(root, read_allowlist(security / "usage-strings-allowlist.txt", report), report)
    check_dependencies(root, read_allowlist(security / "dependencies-allowlist.txt", report), report)
    check_hardened_runtime(root, report)
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
