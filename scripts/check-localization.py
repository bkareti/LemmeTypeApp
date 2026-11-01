#!/usr/bin/env python3
"""Localization readiness check (E7-S7).

Checks that a translator could take the catalog as it is:

1. No user-visible string bypasses the module bundle. SwiftUI's string-literal
   initializers (`Text("…")`, `Button("…")`) look in the main bundle, so inside
   the UI package they would silently never be translated. Use
   `String(localized:…, bundle: .module)` or `Text(verbatim:)`.
2. Dates, numbers, and sizes are never built by hand (`String(format:`,
   `DateFormatter()`, "MB"/"GB" suffixes); use `.formatted(...)`.
3. The committed catalog has every string Xcode extracts (no missing or stale
   entries), and the strings listed as ambiguous carry a translator comment.

    scripts/check-localization.py --literals-only [--root DIR]   fast, source only
    scripts/check-localization.py                                also exports from Xcode (about 20 s)
    scripts/check-localization.py --update                       rewrites the catalog from Xcode
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

UI_SOURCES = "Packages/LemmeTypeKit/Sources/UI"
CATALOG = "Packages/LemmeTypeKit/Sources/UI/Resources/Localizable.xcstrings"

# Strings a translator cannot translate correctly without context (a verb or a noun?).
AMBIGUOUS = (
    "Copy", "Delete", "Insert", "Edit", "Save", "Remove", "Stop", "Pause", "Resume", "Retry", "Back", "Done",
    "Discard", "Dismiss", "Mode", "Style", "Format", "Length", "Tone", "Message", "Email", "Original", "Output",
    "Test", "Off", "OK", "Name", "Mac", "App", "Recording", "Writing", "Cleanup", "Started", "Stopped", "Ready",
    "Profile", "Language", "Engine", "Casual", "Friendly", "Professional", "Concise", "Neutral", "Plain text",
    "Bullet list", "Updates", "Channel", "History", "Overview", "Privacy",
)  # fmt: skip

LITERAL_VIEWS = (
    "Text", "Label", "Button", "Toggle", "Picker", "Section", "TextField", "SecureField", "GroupBox",
    "DisclosureGroup", "LabeledContent", "Menu", "Link",
)  # fmt: skip
LITERAL = re.compile(r"(?<![\w.])(?:%s)\(\s*\"" % "|".join(LITERAL_VIEWS))
LITERAL_MODIFIERS = re.compile(r"\.(?:help|accessibilityLabel|accessibilityHint|navigationTitle)\(\s*\"")
HAND_FORMATTING = re.compile(r"String\(format:|DateFormatter\(\)|NumberFormatter\(\)|\"\s*(?:MB|GB|KB)\b|\b(?:MB|GB)\"")


def source_problems(root: Path) -> list[str]:
    problems: list[str] = []
    for path in sorted((root / UI_SOURCES).rglob("*.swift")):
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            code = line.split("//", 1)[0] if "http" not in line else line
            where = f"{path.relative_to(root)}:{number}"
            if LITERAL.search(code) or LITERAL_MODIFIERS.search(code):
                problems.append(f"{where}: a literal bypasses the module bundle; use String(localized:…, bundle: .module) or Text(verbatim:)")
            if HAND_FORMATTING.search(code):
                problems.append(f"{where}: format dates, numbers, and sizes with .formatted(...), not by hand")
    return problems


def catalog_problems(path: Path) -> list[str]:
    if not path.is_file():
        return [f"missing {path}"]
    strings = json.loads(path.read_text(encoding="utf-8")).get("strings", {})
    problems = []
    for key in AMBIGUOUS:
        entry = strings.get(key)
        if entry is None:
            problems.append(f"catalog has no '{key}' entry (run make l10n-update)")
        elif not str(entry.get("comment", "")).strip():
            problems.append(f"'{key}' is ambiguous and needs a translator comment")
    for key, entry in strings.items():
        if entry.get("extractionState") == "stale":
            problems.append(f"'{key}' is stale: no code uses it any more")
    return problems


def export_catalog(root: Path) -> Path:
    """Runs Xcode's exporter, which refreshes the catalog from the Swift sources."""
    subprocess.run(["xcodegen", "generate", "--quiet"], cwd=root, check=True)
    out = root / "build" / "l10n"
    shutil.rmtree(out, ignore_errors=True)
    result = subprocess.run(
        ["xcodebuild", "-exportLocalizations", "-project", "LemmeType.xcodeproj", "-scheme", "LemmeType",
         "-localizationPath", str(out), "-exportLanguage", "en", "-derivedDataPath", "build/DerivedData"],
        cwd=root, capture_output=True, text=True,
    )  # fmt: skip
    if result.returncode != 0:
        print(result.stdout[-2000:], result.stderr[-2000:], file=sys.stderr)
        raise SystemExit("error: xcodebuild -exportLocalizations failed")
    return root / CATALOG


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--literals-only", action="store_true")
    parser.add_argument("--update", action="store_true")
    args = parser.parse_args()
    root = args.root.resolve()

    problems = source_problems(root)
    if args.update:
        export_catalog(root)
        print("Catalog refreshed from the Swift sources.")
    elif not args.literals_only:
        catalog = root / CATALOG
        before = catalog.read_text(encoding="utf-8") if catalog.is_file() else ""
        export_catalog(root)
        after = catalog.read_text(encoding="utf-8")
        if after != before:
            catalog.write_text(before, encoding="utf-8")  # a check never changes the tree
            old, new = (set(json.loads(t).get("strings", {})) if t else set() for t in (before, after))
            missing = sorted(new - old)
            problems.append(
                f"the catalog is out of date: {len(missing)} string(s) missing, for example {missing[:3]}; run make l10n-update"
            )
    if not args.literals_only or args.update:
        problems += catalog_problems(root / CATALOG)

    if problems:
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        return 1
    if args.literals_only:
        print("No string bypasses the module bundle and nothing is formatted by hand.")
    else:
        print("Localization is ready: no bypassing literals, no hand formatting, a complete commented catalog.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
