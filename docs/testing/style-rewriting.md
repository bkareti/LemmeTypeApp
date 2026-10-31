# Tone and style rewriting — evaluation and thresholds (E10-S5)

**Status: Proposed — awaiting product-owner approval.** Epic 10 cannot be
accepted until these numbers are approved or replaced.

- Approved by / date: —

## Proposed thresholds

| Metric | Proposed limit | How it is measured |
|---|---|---|
| Combinations that keep names, numbers, dates, negation, and commitments | ≥ 90 % of the 31 combinations, on every fixture sentence | `FoundationModelsStyleTests` (opt-in) and the human rubric below |
| Human meaning rubric (below), English | ≥ 95 % of corpus items pass | Two reviewers, a third resolves disagreements |
| Latency: dictation shown → rewrite shown, short text (≤ 40 words) | ≤ 3 s typical, ≤ 15 s worst | `rewriteSeconds` in `session.review` diagnostics; opt-in test |
| Memory | No measurable increase beyond the system model (the model is Apple's, not loaded by LemmeType) | Activity Monitor on a real Mac |
| Network | None | `scripts/check-network-silence.sh` |

## Automated versus real-device

| Check | Where it runs |
|---|---|
| Choices, instruction wording, migration, Exact bypass | CI (`StyleOptionsTests`) |
| Preservation rules, 36-case fixture corpus | CI (`PreservationCheckerTests`) |
| Pipeline, failures, review, Regenerate | CI (`StyleRewritingPipelineTests`, `RecordingCoordinatorStyleTests`, `StyleRewritingEndToEndTests`) |
| Real model on every combination | Opt-in: `LEMMETYPE_REAL_REWRITE=1 swift test --filter FoundationModelsStyleTests` on a Mac with Apple Intelligence |
| Human rubric, VoiceOver, unsupported language, offline | Manual: `manual-acceptance.md` MA-51 … MA-53 |

## Measured so far

- 2026-11-01, development Mac, one synthetic sentence ("Tell Priya that I will
  not be at the review on Friday but I will send the 3 slides tomorrow."): all
  31 combinations in about 17 s; at least 90 % passed the preservation check
  after the instruction wording was corrected (80 % before: the model dropped
  the name when told never to add recipient names). Failures that remain are
  caught by the check and shown as "Not rewritten".

## Human rubric

Same categories as `language-support-matrix.md`: meaning, names, numbers and
dates, negation, intent, and *no invention*. Additionally for style: the tone
and format asked for are recognisable, and a Concise rewrite loses no fact.

## Corpus rules

Synthetic or consented sentences only, no personal data. The fixture corpus in
`PreservationCheckerTests` covers numbers, dates, names, negation,
commitments, links, invented recipients and senders, acceptable rewrites, and
instruction-like dictation; the test fails if a category has no case.
