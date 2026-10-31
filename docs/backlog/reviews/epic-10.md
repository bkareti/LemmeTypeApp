# Readiness review — Epic 10 (tone and style rewriting for new dictation)

Reviewed 2026-10-31 with the `story-review` skill against
`docs/backlog/epic-10-tone-and-style.md`, issue #83, and the code on `main`
(`TextRewriting`, `FoundationModelsRewriter`, `DictationMode`, pipeline,
personalization archive), and ADRs 0014, 0018, 0019, 0021.

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E10-S1 Engine and choices ADR | Ready with notes | Foundation Models support per combination needs a real Apple Intelligence Mac. |
| E10-S2 Style in modes and migration | Ready | `DictationMode` needs a tolerant decoder; archive format stays version 1. |
| E10-S3 Rewrite step | Ready | Reuses `TextRewriting`; adds a deterministic preservation check. |
| E10-S4 Preview and regenerate | Ready | Builds on the review state added by Epic 9. |
| E10-S5 Validation | Ready with notes | Threshold approval and real-device runs are manual. |

No blockers. Epic 10 builds on Epic 9's review state, so it is developed on top
of the Epic 9 branch and merged after it.

## Checklist (epic level)

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Tone and format without retyping. |
| 2 | Size | Pass | Five stories, none above 8 points. |
| 3 | Dependencies | Concern | Needs Epic 9's review state (E9-S5); otherwise merged. |
| 4 | Acceptance criteria | Concern | Quality thresholds are "Proposed" until approved. |
| 5 | CI testability | Concern | A fake rewriter covers logic; the real model is opt-in (`LEMMETYPE_REAL_REWRITE=1`). |
| 6 | Privacy | Pass | On device only; no history; canaries. |
| 7 | Permissions | Pass | No new permission. |
| 8 | Feasibility | Concern | The model must support the dictation language; unsupported languages skip the rewrite with a reason. |
| 9 | Out of scope | Pass | No second selected-text editor, no cloud, no mobile. |
| 10 | Open decisions | Concern | See below. |

## Decisions to record (proposed defaults)

1. **Engine** — the existing `TextRewriting` contract and Foundation Models
   rewriter; no new engine, model, or dependency.
2. **Choices** — tone Neutral, Professional, Friendly, Casual; format Plain
   text, Message, Email, Bullet list; length Original, Concise.
3. **No rewrite** — Neutral + Plain text + Original never calls the model.
4. **Exact bypass** — style is ignored when the writing mode is Exact.
5. **Order** — recognise → write → personalise → **rewrite** → context format.
6. **Safety** — dictated text is data in a fenced passage; the instruction is
   fixed wording from the choices. A deterministic check rejects results that
   drop or change numbers, names, dates, or negation, or add recipients, links,
   or numbers.
7. **Failure** — the original is kept and shown with the reason; never
   reported as a rewrite.
8. **Preview** — always, with Insert, Use Original, Regenerate, Copy, Discard.

## AC → verification map

| Acceptance area | Verification |
|---|---|
| Final choices, no-rewrite combination | `StyleOptionsTests` |
| Migration and Exact bypass | `DictationModeTests`, `PersonalizationArchiveTests` |
| Instruction wording, injection safety | `StyleInstructionTests` |
| Meaning preservation and rejection | `PreservationCheckerTests`, fixture corpus |
| Pipeline, failures, preview | `StyleRewritingPipelineTests`, `RecordingCoordinatorTests` |
| No history, canaries | `StyleRewritingEndToEndTests` |
| Real model quality and latency | Opt-in `LEMMETYPE_REAL_REWRITE=1`, manual acceptance |
