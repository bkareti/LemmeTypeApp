#!/usr/bin/env python3
"""Create the LemmeType GitHub epics and development-ready sub-issues.

The committed Markdown files are the planning source of truth. This script is
idempotent by exact issue title and can safely resume after an interrupted run.
It requires an authenticated GitHub CLI with access to the target repository.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPOSITORY = "bkareti/LemmeTypeApp"
ROOT = Path(__file__).resolve().parents[2]
ROADMAP_PATH = ROOT / "docs" / "roadmap.md"
EPIC_1_PATH = ROOT / "docs" / "backlog" / "epic-01-macos-foundation.md"
EPIC_2_PATH = ROOT / "docs" / "backlog" / "epic-02-local-dictation.md"

LABELS = {
    "epic": ("5319e7", "Product outcome containing related delivery stories"),
    "user-story": ("0e8a16", "User-centered unit of product delivery"),
    "ready-for-development": ("1d76db", "Refined, testable, and ready to implement"),
    "platform:macOS": ("c5def5", "Applies to the macOS application"),
    "phase:mvp": ("fbca04", "Required for the first usable product release"),
    "future": ("d9d9d9", "Planned after core MVP validation"),
    "area:foundation": ("bfdadc", "Application foundation and lifecycle"),
    "area:audio": ("d4c5f9", "Microphone capture and recorder lifecycle"),
    "area:transcription": ("f9d0c4", "Speech recognition and transcript processing"),
    "area:text-delivery": ("fef2c0", "Insertion, paste, and target application behavior"),
}

EPIC_LABELS = {
    1: ["epic", "platform:macOS", "phase:mvp", "area:foundation", "area:audio"],
    2: ["epic", "platform:macOS", "phase:mvp", "area:transcription", "area:text-delivery"],
    3: ["epic", "platform:macOS", "future"],
    4: ["epic", "platform:macOS", "future"],
    5: ["epic", "platform:macOS", "future"],
    6: ["epic", "platform:macOS", "phase:mvp"],
    7: ["epic", "platform:macOS", "phase:mvp"],
    8: ["epic", "future"],
}

STORY_AREA_LABELS = {
    "E1-S1": ["area:foundation"],
    "E1-S2": ["area:foundation"],
    "E1-S3": ["area:foundation"],
    "E1-S4": ["area:foundation"],
    "E1-S5": ["area:audio"],
    "E1-S6": ["area:audio"],
    "E1-S7": ["area:foundation"],
    "E1-S8": ["area:foundation"],
    "E2-S1": ["area:transcription"],
    "E2-S2": ["area:transcription"],
    "E2-S3": ["area:transcription"],
    "E2-S4": ["area:transcription"],
    "E2-S5": ["area:transcription"],
    "E2-S6": ["area:transcription"],
    "E2-S7": ["area:text-delivery"],
    "E2-S8": ["area:text-delivery"],
    "E2-S9": ["area:transcription"],
    "E2-S10": ["area:transcription", "area:text-delivery"],
}


@dataclass(frozen=True)
class IssueSpec:
    key: str
    title: str
    body: str
    labels: list[str]


def gh(*args: str, json_output: bool = False) -> object | str:
    command = ["gh", *args]
    result = subprocess.run(
        command,
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise RuntimeError(f"Command failed: {' '.join(command)}\n{detail}")
    output = result.stdout.strip()
    return json.loads(output) if json_output and output else output


def ensure_labels() -> None:
    for name, (color, description) in LABELS.items():
        gh(
            "label",
            "create",
            name,
            "--repo",
            REPOSITORY,
            "--color",
            color,
            "--description",
            description,
            "--force",
        )


def roadmap_epics() -> list[IssueSpec]:
    text = ROADMAP_PATH.read_text(encoding="utf-8")
    matches = list(re.finditer(r"^## Epic (\d+) — (.+)$", text, re.MULTILINE))
    specs: list[IssueSpec] = []
    for index, match in enumerate(matches):
        number = int(match.group(1))
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        if number == 8:
            dependency_order = text.find("## Dependency order", match.end())
            if dependency_order != -1:
                end = dependency_order
        body = text[match.end() : end].strip()
        if number in (1, 2):
            source_path = EPIC_1_PATH if number == 1 else EPIC_2_PATH
            source = source_path.read_text(encoding="utf-8")
            body_start = source.index("## Epic issue body") + len("## Epic issue body")
            first_story = re.search(r"^## E[12]-S1 —", source, re.MULTILINE)
            if first_story is None:
                raise RuntimeError(f"No first story found in {source_path}")
            body = source[body_start : first_story.start()].strip().removesuffix("---").strip()
        relative = (EPIC_1_PATH if number == 1 else EPIC_2_PATH if number == 2 else ROADMAP_PATH).relative_to(ROOT)
        body += (
            "\n\n## Planning source\n\n"
            f"[`{relative}`](https://github.com/{REPOSITORY}/blob/main/{relative})"
        )
        specs.append(
            IssueSpec(
                key=f"EPIC-{number}",
                title=f"[Epic {number}] {match.group(2)}",
                body=body,
                labels=EPIC_LABELS[number],
            )
        )
    if len(specs) != 8:
        raise RuntimeError(f"Expected 8 epics, found {len(specs)}")
    return specs


def stories(path: Path, epic_number: int, parent_number: int) -> list[IssueSpec]:
    text = path.read_text(encoding="utf-8")
    matches = list(re.finditer(rf"^## (E{epic_number}-S\d+) — (.+)$", text, re.MULTILINE))
    specs: list[IssueSpec] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        body = text[match.end() : end].strip()
        body = re.sub(r"\n---\s*$", "", body).strip()
        body = re.sub(rf"\n## Epic {epic_number} story order.*$", "", body, flags=re.DOTALL).strip()
        relative = path.relative_to(ROOT)
        body += (
            f"\n\n**Parent epic:** #{parent_number}"
            "\n\n## Planning source\n\n"
            f"[`{relative}`](https://github.com/{REPOSITORY}/blob/main/{relative})"
        )
        key = match.group(1)
        labels = [
            "user-story",
            "ready-for-development",
            "platform:macOS",
            "phase:mvp",
            *STORY_AREA_LABELS[key],
        ]
        specs.append(
            IssueSpec(
                key=key,
                title=f"[{key}] {match.group(2)}",
                body=body,
                labels=labels,
            )
        )
    return specs


def existing_issues() -> dict[str, dict[str, object]]:
    data = gh(
        "issue",
        "list",
        "--repo",
        REPOSITORY,
        "--state",
        "all",
        "--limit",
        "200",
        "--json",
        "id,number,title,url,state",
        json_output=True,
    )
    assert isinstance(data, list)
    return {str(issue["title"]): issue for issue in data}


def ensure_issue(spec: IssueSpec, known: dict[str, dict[str, object]]) -> dict[str, object]:
    current = known.get(spec.title)
    if current is not None:
        print(f"exists #{current['number']}: {spec.title}")
        return current

    args = [
        "issue",
        "create",
        "--repo",
        REPOSITORY,
        "--title",
        spec.title,
        "--body",
        spec.body,
    ]
    for label in spec.labels:
        args.extend(["--label", label])
    url = str(gh(*args))
    number = int(url.rstrip("/").split("/")[-1])
    issue = gh(
        "issue",
        "view",
        str(number),
        "--repo",
        REPOSITORY,
        "--json",
        "id,number,title,url,state",
        json_output=True,
    )
    assert isinstance(issue, dict)
    known[spec.title] = issue
    print(f"created #{number}: {spec.title}")
    return issue


def child_ids(parent_id: str) -> set[str]:
    query = """
      query($id: ID!) {
        node(id: $id) {
          ... on Issue {
            subIssues(first: 100) { nodes { id } }
          }
        }
      }
    """
    data = gh(
        "api",
        "graphql",
        "-f",
        f"query={query}",
        "-f",
        f"id={parent_id}",
        json_output=True,
    )
    assert isinstance(data, dict)
    nodes = data["data"]["node"]["subIssues"]["nodes"]
    return {str(node["id"]) for node in nodes}


def add_sub_issue(parent: dict[str, object], child: dict[str, object]) -> None:
    parent_id = str(parent["id"])
    child_id = str(child["id"])
    if child_id in child_ids(parent_id):
        print(f"linked #{child['number']} under #{parent['number']} (already present)")
        return
    mutation = """
      mutation($issue: ID!, $subIssue: ID!) {
        addSubIssue(input: {issueId: $issue, subIssueId: $subIssue}) {
          issue { id }
          subIssue { id }
        }
      }
    """
    gh(
        "api",
        "graphql",
        "-f",
        f"query={mutation}",
        "-f",
        f"issue={parent_id}",
        "-f",
        f"subIssue={child_id}",
        json_output=True,
    )
    print(f"linked #{child['number']} under #{parent['number']}")


def verify(parent: dict[str, object], expected: int) -> None:
    actual = len(child_ids(str(parent["id"])))
    if actual != expected:
        raise RuntimeError(
            f"Epic #{parent['number']} has {actual} sub-issues; expected {expected}"
        )
    print(f"verified #{parent['number']}: {actual} sub-issues")


def main() -> int:
    ensure_labels()
    known = existing_issues()

    epic_issues: dict[int, dict[str, object]] = {}
    for index, spec in enumerate(roadmap_epics(), start=1):
        epic_issues[index] = ensure_issue(spec, known)

    epic_1_stories = stories(EPIC_1_PATH, 1, int(epic_issues[1]["number"]))
    epic_2_stories = stories(EPIC_2_PATH, 2, int(epic_issues[2]["number"]))

    for spec in epic_1_stories:
        child = ensure_issue(spec, known)
        add_sub_issue(epic_issues[1], child)

    for spec in epic_2_stories:
        child = ensure_issue(spec, known)
        add_sub_issue(epic_issues[2], child)

    verify(epic_issues[1], 8)
    verify(epic_issues[2], 10)
    print(
        f"Backlog synchronized: 8 epics and "
        f"{len(epic_1_stories) + len(epic_2_stories)} development stories."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, KeyError, AssertionError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
