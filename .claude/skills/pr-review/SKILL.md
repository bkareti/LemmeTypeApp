---
name: pr-review
description: Review a LemmeType pull request or local branch against its user story, the macOS coding standards, privacy rules, and test evidence. Use when asked to review a PR, a branch, or a diff in this repository, or before a PR is marked ready.
---

# Pull request review

## Gather

```bash
gh pr view <n> --repo bkareti/LemmeTypeApp --json title,body,headRefName,files,statusCheckRollup
gh pr diff <n> --repo bkareti/LemmeTypeApp
```

For a local branch: `git diff main...HEAD`. Identify the story from the title
(`[E1-S4]`) and read it in `docs/backlog/` plus its readiness review in
`docs/backlog/reviews/` if present. Load `macos-coding-standards`.

## Review passes

Do each pass separately; most real bugs are found in 1–3.

1. **Acceptance** — for every acceptance criterion, find the test or manual step
   that proves it. Missing evidence is a finding. Scope creep beyond the story is
   a finding.
2. **Correctness** — state-machine transitions (including invalid ones),
   cancellation, teardown, error paths, device/permission changes mid-operation,
   repeated or bouncing events, app quit/sleep while active.
3. **Concurrency** — main-actor isolation of UI, `Sendable` correctness, stored
   and cancelled `Task`s, no blocking on the audio thread, no
   `@unchecked Sendable` without justification.
4. **Privacy & security** — no logging/persisting of audio, text, clipboard, or
   focused-element contents; `.private` log interpolation; no new network
   access; temporary files deleted; no new entitlements or TCC permissions
   without story justification; no secrets.
5. **Architecture** — module dependency table respected, services built only in
   `AppComposition`, no singletons, new dependencies/modules have an ADR,
   `project.yml` (not the xcodeproj) changed.
6. **macOS UX** — focus never stolen from the target app, accessibility labels,
   VoiceOver announcements, Reduce Motion, localizable strings.
7. **Tests & CI** — tests are deterministic (injected clock, fakes), named for
   behavior, and CI is green. Run `make lint` and `make test` locally when
   reviewing a local branch.

## Report

Rank findings most severe first. For each: file:line, what is wrong, a concrete
failure scenario, and a suggested fix. Separate **Blocking** (correctness,
privacy, missing AC evidence) from **Non-blocking** (style, simplification).
End with a verdict: Approve / Approve with nits / Request changes.

Post comments to GitHub (`gh pr review` / `gh pr comment`) only after the user
confirms; never approve or merge on the user's behalf without being asked.
