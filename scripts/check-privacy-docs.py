#!/usr/bin/env python3
"""Keeps the privacy threat model and release checklist honest (E6-S8).

Every threat row in docs/security/threat-model.md needs a control and at least
one verification, and every verification written in `backticks` must exist: a
test suite in a Tests folder, a script or document in the repository, a `make`
target, or a manual step (MA-n) in docs/testing/manual-acceptance.md. Every
item in docs/security/privacy-release-checklist.md must cite at least one that
exists. A renamed test or deleted step therefore fails CI instead of leaving a
threat that looks covered and is not.

    scripts/check-privacy-docs.py [--root <repository root>]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

THREAT_MODEL = "docs/security/threat-model.md"
CHECKLIST = "docs/security/privacy-release-checklist.md"
MANUAL = "docs/testing/manual-acceptance.md"
TEST_ROOTS = ("Packages/LemmeTypeKit/Tests", "App")
PLACEHOLDERS = {"", "tbd", "todo", "none", "n/a", "-", "—"}


class Resolver:
    """Decides whether a backticked reference points at something real."""

    def __init__(self, root: Path) -> None:
        self.root = root
        self.manual = (root / MANUAL).read_text(encoding="utf-8") if (root / MANUAL).is_file() else ""
        self.makefile = (root / "Makefile").read_text(encoding="utf-8") if (root / "Makefile").is_file() else ""
        self.suites = self._suites()

    def _suites(self) -> set[str]:
        names: set[str] = set()
        for folder in TEST_ROOTS:
            for path in (self.root / folder).rglob("*.swift"):
                text = path.read_text(encoding="utf-8", errors="ignore")
                names |= set(re.findall(r"\b(?:struct|final class|class)\s+([A-Z]\w*Tests)\b", text))
        return names

    def exists(self, token: str) -> bool:
        if re.fullmatch(r"MA-\d+", token):
            return re.search(rf"^\*\*{re.escape(token)}[ *]", self.manual, re.MULTILINE) is not None
        if token.startswith("make "):
            return all(
                re.search(rf"^{re.escape(target)}:", self.makefile, re.MULTILINE)
                for target in token.removeprefix("make ").split()
            )
        if token.startswith("scripts/") or token.startswith("docs/") or "/" in token or "." in token:
            path = token.split()[0]
            return (self.root / path).exists()
        if re.fullmatch(r"[A-Z]\w*Tests", token):
            return token in self.suites
        return (self.root / token).exists()


def backticked(cell: str) -> list[str]:
    return [item.strip() for item in re.findall(r"`([^`]+)`", cell)]


def check_threat_model(root: Path, resolver: Resolver) -> list[str]:
    errors: list[str] = []
    path = root / THREAT_MODEL
    if not path.is_file():
        return [f"missing {THREAT_MODEL}"]
    rows = [line for line in path.read_text(encoding="utf-8").splitlines() if re.match(r"^\|\s*T-\d+\s*\|", line)]
    if not rows:
        errors.append(f"{THREAT_MODEL}: no threat rows (| T-nn | …) found")
    seen: set[str] = set()
    for row in rows:
        cells = [cell.strip() for cell in row.strip().strip("|").split("|")]
        threat_id = cells[0]
        if threat_id in seen:
            errors.append(f"{THREAT_MODEL}: {threat_id} appears twice")
        seen.add(threat_id)
        if len(cells) != 5:
            errors.append(f"{THREAT_MODEL}: {threat_id} needs 5 cells (id, threat, control, verification, residual risk)")
            continue
        _, threat, control, verification, residual = cells
        if threat.lower() in PLACEHOLDERS:
            errors.append(f"{THREAT_MODEL}: {threat_id} has no threat text")
        if control.lower() in PLACEHOLDERS:
            errors.append(f"{THREAT_MODEL}: {threat_id} has no control")
        if residual.lower() in PLACEHOLDERS:
            errors.append(f"{THREAT_MODEL}: {threat_id} has no residual-risk statement (write 'None known' if true)")
        tokens = backticked(verification)
        if not tokens:
            errors.append(f"{THREAT_MODEL}: {threat_id} has no verification in `backticks`")
        for token in tokens:
            if not resolver.exists(token):
                errors.append(f"{THREAT_MODEL}: {threat_id} cites `{token}`, which does not exist")
    return errors


def check_checklist(root: Path, resolver: Resolver) -> list[str]:
    errors: list[str] = []
    path = root / CHECKLIST
    if not path.is_file():
        return [f"missing {CHECKLIST}"]
    items = [line for line in path.read_text(encoding="utf-8").splitlines() if re.match(r"^- \[[ xX]\]", line)]
    if not items:
        errors.append(f"{CHECKLIST}: no checklist items found")
    for item in items:
        tokens = backticked(item)
        label = item[6:60].strip()
        if not tokens:
            errors.append(f"{CHECKLIST}: '{label}…' cites nothing in `backticks`")
        for token in tokens:
            if not resolver.exists(token):
                errors.append(f"{CHECKLIST}: '{label}…' cites `{token}`, which does not exist")
    return errors


def run(root: Path) -> list[str]:
    resolver = Resolver(root)
    return check_threat_model(root, resolver) + check_checklist(root, resolver)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    errors = run(parser.parse_args().root.resolve())
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    print("Every threat and checklist item cites a control or check that exists.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
