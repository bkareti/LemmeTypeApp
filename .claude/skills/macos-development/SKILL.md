---
name: macos-development
description: End-to-end workflow for implementing a LemmeType user story in the macOS app — readiness review, branch, implementation to the coding standards, tests, build/lint, acceptance evidence, and PR. Use whenever asked to implement, build, or start a story (E1-S1, E2-S3, …) or any feature in the Swift codebase.
---

# Implementing a LemmeType story

## 1. Prepare

1. Read the story in `docs/backlog/` and run the `story-review` skill. Do not
   start coding on a "Needs refinement" verdict; resolve blockers with the user.
2. Load the `macos-coding-standards` skill.
3. Branch from up-to-date `main`: `feature/<story-id-lowercase>-<slug>`
   (e.g. `feature/e1-s4-global-shortcut`). One story per branch and PR.

## 2. Build commands

```bash
make bootstrap   # one-time: checks Homebrew tools (xcodegen, swiftlint)
make generate    # regenerate LemmeType.xcodeproj from project.yml
make build       # Debug build of the app
make test        # package unit tests + app unit tests + UI tests
make test-unit   # fast: swift test on Packages/LemmeTypeKit only
make lint        # swift-format lint + swiftlint
make format      # apply swift-format
make run         # build and launch the Debug app
```

Single test: `swift test --package-path Packages/LemmeTypeKit --filter
DomainTests.RecorderStateTests` or `xcodebuild test ... -only-testing:LemmeTypeTests/AppCompositionTests`.

Regenerate the Xcode project after adding/removing files in the app or test
targets or editing `project.yml`.

## 3. Implement

- Start from Domain: protocol + model + state machine + tests, then the
  platform implementation, then UI, then wire it in `AppComposition`.
- Write the tests for each acceptance criterion as you go; keep the
  AC → test map from the readiness review current.
- Anything that cannot be automated (TCC prompts, real microphone, other apps)
  goes in `docs/testing/manual-acceptance.md` as a numbered, repeatable step.
- Record any decision a future developer would need in `docs/decisions/NNNN-*.md`
  (context, decision, consequences). Update `CLAUDE.md` when commands or
  architecture change.

## 4. Verify before opening a PR

- `make lint` and `make test` pass with no new warnings.
- Launch the app (`make run`) and exercise the story's user flow; note what was
  checked manually and what could not be.
- Search the diff for privacy violations: `print(`, `NSLog`, `URLSession`,
  logging of payloads, retained audio/text.
- Every acceptance criterion has evidence (test name, manual step, or screenshot).

## 5. Pull request

Commit and push only when the user asks. PR title: `[E1-S4] <story title>`.
Body:

```markdown
Closes #<issue>

## Summary
## Acceptance criteria
- [x] <criterion> — <evidence: test name / manual step>
## Decisions
## Manual verification
## Not done / follow-ups
```

Then run the `pr-review` skill on the PR before requesting human review.
