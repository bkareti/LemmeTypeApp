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
EPIC_3_PATH = ROOT / "docs" / "backlog" / "epic-03-context-aware-writing.md"
EPIC_4_PATH = ROOT / "docs" / "backlog" / "epic-04-personalization.md"
EPIC_5_PATH = ROOT / "docs" / "backlog" / "epic-05-model-management.md"
EPIC_6_PATH = ROOT / "docs" / "backlog" / "epic-06-privacy-security.md"
EPIC_7_PATH = ROOT / "docs" / "backlog" / "epic-07-quality-release.md"
EPIC_8_PATH = ROOT / "docs" / "backlog" / "epic-08-ios-companion.md"
EPIC_9_PATH = ROOT / "docs" / "backlog" / "epic-09-multilingual-dictation.md"
EPIC_10_PATH = ROOT / "docs" / "backlog" / "epic-10-tone-and-style.md"
EPIC_11_PATH = ROOT / "docs" / "backlog" / "epic-11-cloud-speech.md"
EPIC_12_PATH = ROOT / "docs" / "backlog" / "epic-12-iphone-cloud-english.md"
EPIC_13_PATH = ROOT / "docs" / "backlog" / "epic-13-paid-launch.md"
# Refined epics: number -> (backlog file, story phase label, expected story count).
REFINED_EPICS = {
    1: (EPIC_1_PATH, "phase:mvp", 8),
    2: (EPIC_2_PATH, "phase:mvp", 10),
    3: (EPIC_3_PATH, "phase:post-mvp", 7),
    4: (EPIC_4_PATH, "phase:post-mvp", 9),
    5: (EPIC_5_PATH, "phase:post-mvp", 7),
    6: (EPIC_6_PATH, "phase:mvp", 8),
    7: (EPIC_7_PATH, "phase:mvp", 9),
    8: (EPIC_8_PATH, "phase:post-mvp", 9),
    9: (EPIC_9_PATH, "phase:post-mvp", 6),
    10: (EPIC_10_PATH, "phase:post-mvp", 5),
    11: (EPIC_11_PATH, "phase:post-mvp", 4),
    12: (EPIC_12_PATH, "phase:post-mvp", 4),
    13: (EPIC_13_PATH, "phase:post-mvp", 8),
}
# Epics 9 through 13 are not in roadmap.md; their title comes from the backlog file heading.
BACKLOG_ONLY_EPICS = (9, 10, 11, 12, 13)
EPIC_COUNT = 8 + len(BACKLOG_ONLY_EPICS)

LABELS = {
    "epic": ("5319e7", "Product outcome containing related delivery stories"),
    "user-story": ("0e8a16", "User-centered unit of product delivery"),
    "ready-for-development": ("1d76db", "Refined, testable, and ready to implement"),
    "platform:macOS": ("c5def5", "Applies to the macOS application"),
    "platform:iOS": ("c5def5", "Applies to the iPhone and iPad application"),
    "phase:mvp": ("fbca04", "Required for the first usable product release"),
    "phase:post-mvp": ("f9e79f", "Refined work that follows the first usable release"),
    "future": ("d9d9d9", "Planned after core MVP validation"),
    "area:foundation": ("bfdadc", "Application foundation and lifecycle"),
    "area:audio": ("d4c5f9", "Microphone capture and recorder lifecycle"),
    "area:transcription": ("f9d0c4", "Speech recognition and transcript processing"),
    "area:text-delivery": ("fef2c0", "Insertion, paste, and target application behavior"),
    "area:context": ("c2e0c6", "Cursor context capture, policy, and context-aware formatting"),
    "area:voice-editing": ("e99695", "Selected-text editing with an on-device language model"),
    "area:personalization": ("bfd4f2", "Vocabulary, replacements, snippets, and personalization data"),
    "area:modes": ("d4c5f9", "Dictation modes and per-application mode rules"),
    "area:models": ("f9d0c4", "Model catalog, downloads, verification, and model settings"),
    "area:performance": ("c2e0c6", "Model residency, performance profiles, and system conditions"),
    "area:mobile": ("d4c5f9", "iPhone and iPad app, App Intents, and iOS platform work"),
    "area:privacy": ("0e8a16", "Data inventory, retention, history, and privacy controls"),
    "area:security": ("b60205", "Network, entitlement, dependency, and threat-model guardrails"),
    "area:release": ("1d76db", "Packaging, signing, notarization, updates, and rollback"),
    "area:quality": ("fbca04", "Accessibility, localization, compatibility, and the quality gate"),
    "area:backend": ("5319e7", "The speech gateway server, its API, hosting, and operations"),
    "area:billing": ("fef2c0", "Subscriptions, trials, entitlement checks, and usage limits"),
    "beta-feedback": ("d93f0b", "Report from a beta tester (see docs/release/beta-program.md)"),
    "release-blocker": ("b60205", "A published build that should be withdrawn (see docs/release/rollback.md)"),
}

EPIC_LABELS = {
    1: ["epic", "platform:macOS", "phase:mvp", "area:foundation", "area:audio"],
    2: ["epic", "platform:macOS", "phase:mvp", "area:transcription", "area:text-delivery"],
    3: ["epic", "platform:macOS", "phase:post-mvp", "area:context", "area:voice-editing"],
    4: ["epic", "platform:macOS", "phase:post-mvp", "area:personalization", "area:modes"],
    5: ["epic", "platform:macOS", "phase:post-mvp", "area:models", "area:performance"],
    6: ["epic", "platform:macOS", "phase:mvp", "area:privacy", "area:security"],
    7: ["epic", "platform:macOS", "phase:mvp", "area:release", "area:quality"],
    8: ["epic", "platform:iOS", "phase:post-mvp", "area:mobile"],
    9: ["epic", "platform:macOS", "phase:post-mvp", "area:transcription"],
    10: ["epic", "platform:macOS", "phase:post-mvp", "area:voice-editing", "area:modes"],
    11: ["epic", "platform:macOS", "phase:post-mvp", "area:transcription", "area:privacy", "area:security"],
    12: ["epic", "platform:iOS", "phase:post-mvp", "area:mobile", "area:transcription", "area:privacy"],
    13: ["epic", "platform:iOS", "phase:post-mvp", "area:mobile", "area:backend", "area:billing"],
}

# Stories carry the macOS label unless their epic is listed here.
EPIC_PLATFORM_LABELS = {8: "platform:iOS", 12: "platform:iOS", 13: "platform:iOS"}

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
    "E3-S1": ["area:context"],
    "E3-S2": ["area:context"],
    "E3-S3": ["area:context"],
    "E3-S4": ["area:voice-editing"],
    "E3-S5": ["area:voice-editing"],
    "E3-S6": ["area:context"],
    "E3-S7": ["area:context", "area:voice-editing"],
    "E4-S1": ["area:personalization"],
    "E4-S2": ["area:personalization", "area:transcription"],
    "E4-S3": ["area:personalization"],
    "E4-S4": ["area:personalization"],
    "E4-S5": ["area:modes"],
    "E4-S6": ["area:modes"],
    "E4-S7": ["area:modes"],
    "E4-S8": ["area:personalization", "area:modes"],
    "E4-S9": ["area:personalization", "area:modes"],
    "E5-S1": ["area:models"],
    "E5-S2": ["area:models"],
    "E5-S3": ["area:models"],
    "E5-S4": ["area:performance"],
    "E5-S5": ["area:performance"],
    "E5-S6": ["area:performance"],
    "E5-S7": ["area:models", "area:performance"],
    "E6-S1": ["area:privacy"],
    "E6-S2": ["area:security", "area:privacy"],
    "E6-S3": ["area:privacy"],
    "E6-S4": ["area:privacy"],
    "E6-S5": ["area:privacy"],
    "E6-S6": ["area:privacy", "area:security"],
    "E6-S7": ["area:security"],
    "E6-S8": ["area:security", "area:privacy"],
    "E7-S1": ["area:release"],
    "E7-S2": ["area:release"],
    "E7-S3": ["area:release", "area:privacy"],
    "E7-S4": ["area:quality", "area:foundation"],
    "E7-S5": ["area:quality"],
    "E7-S6": ["area:quality"],
    "E7-S7": ["area:quality"],
    "E7-S8": ["area:quality", "area:release"],
    "E7-S9": ["area:release"],
    "E8-S1": ["area:mobile"],
    "E8-S2": ["area:mobile", "area:quality"],
    "E8-S3": ["area:mobile", "area:foundation"],
    "E8-S4": ["area:mobile", "area:audio"],
    "E8-S5": ["area:mobile", "area:models", "area:transcription"],
    "E8-S6": ["area:mobile", "area:text-delivery"],
    "E8-S7": ["area:mobile"],
    "E8-S8": ["area:mobile", "area:personalization", "area:modes"],
    "E8-S9": ["area:mobile", "area:privacy", "area:quality"],
    "E9-S1": ["area:transcription"],
    "E9-S2": ["area:transcription"],
    "E9-S3": ["area:transcription"],
    "E9-S4": ["area:transcription"],
    "E9-S5": ["area:transcription"],
    "E9-S6": ["area:transcription"],
    "E10-S1": ["area:voice-editing", "area:modes"],
    "E10-S2": ["area:voice-editing", "area:modes"],
    "E10-S3": ["area:voice-editing", "area:modes"],
    "E10-S4": ["area:voice-editing", "area:modes"],
    "E10-S5": ["area:voice-editing", "area:modes"],
    "E11-S1": ["area:transcription", "area:security"],
    "E11-S2": ["area:transcription"],
    "E11-S3": ["area:transcription", "area:privacy"],
    "E11-S4": ["area:privacy", "area:security", "area:quality"],
    "E12-S1": ["area:mobile", "area:transcription", "area:privacy"],
    "E12-S2": ["area:mobile", "area:transcription"],
    "E12-S3": ["area:mobile", "area:modes"],
    "E12-S4": ["area:mobile", "area:privacy", "area:quality"],
    "E13-S1": ["area:backend", "area:transcription", "area:privacy"],
    "E13-S2": ["area:backend", "area:billing", "area:security"],
    "E13-S3": ["area:mobile", "area:transcription", "area:privacy"],
    "E13-S4": ["area:mobile", "area:billing"],
    "E13-S5": ["area:mobile", "area:billing"],
    "E13-S6": ["area:mobile", "area:audio", "area:privacy"],
    "E13-S7": ["area:mobile", "area:audio", "area:security"],
    "E13-S8": ["area:mobile", "area:privacy", "area:release"],
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


def refined_epic_body(number: int) -> tuple[str, Path]:
    source_path = REFINED_EPICS[number][0]
    source = source_path.read_text(encoding="utf-8")
    body_start = source.index("## Epic issue body") + len("## Epic issue body")
    first_story = re.search(rf"^## E{number}-S1 —", source, re.MULTILINE)
    if first_story is None:
        raise RuntimeError(f"No first story found in {source_path}")
    body = source[body_start : first_story.start()].strip().removesuffix("---").strip()
    return body, source_path


def with_planning_source(body: str, source_path: Path) -> str:
    relative = source_path.relative_to(ROOT)
    return (
        f"{body}\n\n## Planning source\n\n"
        f"[`{relative}`](https://github.com/{REPOSITORY}/blob/main/{relative})"
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
        source_path = ROADMAP_PATH
        if number in REFINED_EPICS:
            body, source_path = refined_epic_body(number)
        specs.append(
            IssueSpec(
                key=f"EPIC-{number}",
                title=f"[Epic {number}] {match.group(2)}",
                body=with_planning_source(body, source_path),
                labels=EPIC_LABELS[number],
            )
        )
    specs.extend(backlog_only_epics())
    if len(specs) != EPIC_COUNT:
        raise RuntimeError(f"Expected {EPIC_COUNT} epics, found {len(specs)}")
    return specs


def backlog_only_epics() -> list[IssueSpec]:
    specs: list[IssueSpec] = []
    for number in BACKLOG_ONLY_EPICS:
        body, source_path = refined_epic_body(number)
        heading = re.search(
            rf"^# Epic {number} — (.+)$",
            source_path.read_text(encoding="utf-8"),
            re.MULTILINE,
        )
        if heading is None:
            raise RuntimeError(f"No '# Epic {number} — Title' heading in {source_path}")
        title = heading.group(1)
        specs.append(
            IssueSpec(
                key=f"EPIC-{number}",
                title=f"[Epic {number}] {title[0].upper()}{title[1:]}",
                body=with_planning_source(body, source_path),
                labels=EPIC_LABELS[number],
            )
        )
    return specs


def stories(path: Path, epic_number: int, parent_number: int, phase: str) -> list[IssueSpec]:
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
            EPIC_PLATFORM_LABELS.get(epic_number, "platform:macOS"),
            phase,
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
    for spec in roadmap_epics():
        epic_issues[int(spec.key.removeprefix("EPIC-"))] = ensure_issue(spec, known)

    story_count = 0
    for number, (path, phase, expected) in REFINED_EPICS.items():
        epic_stories = stories(path, number, int(epic_issues[number]["number"]), phase)
        if len(epic_stories) != expected:
            raise RuntimeError(f"{path.name} has {len(epic_stories)} stories; expected {expected}")
        for spec in epic_stories:
            child = ensure_issue(spec, known)
            add_sub_issue(epic_issues[number], child)
        story_count += len(epic_stories)

    for number, (_, _, expected) in REFINED_EPICS.items():
        verify(epic_issues[number], expected)
    print(f"Backlog synchronized: {EPIC_COUNT} epics and {story_count} development stories.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, KeyError, AssertionError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
