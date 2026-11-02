#!/usr/bin/env python3
"""Checks that the release, support, and testing documents point at things that exist (E7-S9).

For each document it checks:
  - relative Markdown links  [text](path)           -> the file exists (anchors and URLs are skipped)
  - repository paths in `backticks`                 -> scripts/…, docs/…, Config/…, .github/…, App/…, Packages/…
  - `make target` in backticks                      -> the Makefile has the target
Generated paths (build/…), placeholders (<…>, X.Y.Z), and wildcards are skipped.

    scripts/check-doc-links.py [--root <repository root>]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

DOCUMENTS = (
    "README.md", "CHANGELOG.md", "docs/release/*.md", "docs/testing/compatibility-matrix.md",
    ".claude/skills/release-management/SKILL.md",
)  # fmt: skip
REPO_PREFIXES = ("scripts/", "docs/", "Config/", ".github/", "App/", "Packages/", "Makefile", "CHANGELOG.md", "README.md", "THIRD_PARTY_NOTICES.md")
# Files that exist only on a developer's Mac (gitignored on purpose).
LOCAL_ONLY = {"Config/Signing.local.xcconfig"}
SKIP = re.compile(r"[<>*]|X\.Y\.Z|\bvX\b|\.\.\.|…")


def targets(makefile: Path) -> set[str]:
    return set(re.findall(r"^([A-Za-z0-9_.-]+):", makefile.read_text(encoding="utf-8"), re.MULTILINE)) if makefile.is_file() else set()


def check_document(root: Path, path: Path, make_targets: set[str]) -> list[str]:
    errors: list[str] = []
    text = path.read_text(encoding="utf-8")
    relative = path.relative_to(root)
    for target in re.findall(r"\]\(([^)\s]+)\)", text):
        if re.match(r"[a-z]+:", target) or target.startswith("#"):
            continue
        file = target.split("#", 1)[0]
        if file and not (path.parent / file).exists():
            errors.append(f"{relative}: the link ({target}) points at nothing")
    for token in re.findall(r"`([^`\n]+)`", text):
        token = token.strip()
        if SKIP.search(token):
            continue
        if token.startswith("make ") and re.fullmatch(r"make [a-z0-9-]+", token):
            if token.removeprefix("make ") not in make_targets:
                errors.append(f"{relative}: `{token}` is not a Makefile target")
        elif token in LOCAL_ONLY:
            continue
        elif token.startswith(REPO_PREFIXES) and " " not in token and not token.endswith("/"):
            if not (root / token).exists():
                errors.append(f"{relative}: `{token}` does not exist")
    return errors


def run(root: Path) -> list[str]:
    make_targets = targets(root / "Makefile")
    errors: list[str] = []
    seen = 0
    for pattern in DOCUMENTS:
        for path in sorted(root.glob(pattern)):
            seen += 1
            errors += check_document(root, path, make_targets)
    if seen == 0:
        errors.append("no documents found to check")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    errors = run(parser.parse_args().root.resolve())
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    print("Every link and repository path in the release and support documents exists.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
