---
name: story-review
description: Review LemmeType user stories (docs/backlog/*.md or GitHub issues) for development readiness before any code is written — testability, scope, dependencies, privacy, permissions, and open technical decisions. Use when asked to review, refine, or check readiness of a story or epic, and always as the first step of the macos-development skill.
---

# Story readiness review

Goal: decide whether a story can be implemented and accepted without guessing,
and surface every decision the developer would otherwise make silently.

## Inputs

- The story section in `docs/backlog/epic-NN-*.md` (source of truth), or the
  GitHub issue (`gh issue view <n> --repo bkareti/LemmeTypeApp`).
- Its epic's "Epic issue body" and exit criteria in `docs/roadmap.md`.
- `docs/product-brief.md` non-goals and `docs/decisions/` ADRs.
- The current code, for dependencies the story assumes already exist.

## Checklist

For each item record **Pass**, **Concern**, or **Blocker** with a one-line reason.

1. **Value** — the user story names a real user and outcome; scope matches it.
2. **Size** — fits in one PR (≤ 8 points). 13-point stories need a split proposal.
3. **Dependencies** — every listed dependency is merged, or the gap is called
   out. Look for unlisted dependencies (e.g. a protocol another story owns).
4. **Acceptance criteria** — each criterion is observable and has a clear
   verification method: automated test, UI test, or manual checklist. Flag
   vague words ("quickly", "useful", "clear") that lack a threshold.
5. **Testability on CI** — identify criteria that need real hardware, TCC
   prompts, or a GUI session, and require a fake/protocol seam or a manual
   checklist entry for them.
6. **Privacy** — what data is touched (audio, text, clipboard, focused element,
   app identity)? Is retention, logging, and deletion specified? Anything that
   conflicts with the coding-standards privacy rules is a Blocker.
7. **Permissions** — which TCC permissions are needed; the story must not
   require Screen Recording or Input Monitoring unless it justifies them.
8. **macOS feasibility** — check the API really exists for the deployment
   target and works for a sandboxed/unsandboxed, non-App-Store build as
   planned (e.g. global shortcuts, non-activating panels, SMAppService).
9. **Out of scope** — explicit; nothing in scope belongs to a later epic.
10. **Open decisions** — list technical/UX decisions the story leaves open and
    propose a default for each.

## Output

Write the review to `docs/backlog/reviews/<story-or-epic-id>.md`:

```markdown
# Readiness review — E1-S4 <title>
Verdict: Ready | Ready with notes | Needs refinement
| # | Check | Result | Notes |
...
## Decisions to record (proposed defaults)
## Suggested story edits
## AC → verification map
| Acceptance criterion | Verification (test name / UI test / manual checklist) |
```

Then summarise the verdict and blockers in chat.

## Editing the backlog

- Only edit a story's text when the user agrees with the suggested edits.
- Never change a story heading (`## E1-S4 — …`): `sync_backlog.py` matches
  issues by exact title, so a rename creates a duplicate issue.
- Edits to bodies are not pushed to existing GitHub issues by the sync script;
  tell the user if the issue needs a manual update.
