# 0024 — Opt-in tone and style rewriting for new dictation

- Status: Accepted (thresholds Proposed)
- Date: 2026-11-01
- Stories: E10-S1 … E10-S5 (issues #92–#96, epic #83)

## Context

Epic 3 can rewrite *selected* text on request (ADR 0018, 0019). Epic 4's style is
deterministic only and excluded model-based tone changes (ADR 0021). Users now
want newly dictated text turned into a polite email or a short message, with
the option to see and keep the original — including text translated to English
by Epic 9 (ADR 0023).

## Decision

- **Engine** — reuse `TextRewriting` and the Foundation Models rewriter. No new
  engine, model, dependency, or network path. There is no second selected-text
  editor.
- **Choices** (final) — three independent settings saved in a `DictationMode`:
  tone (Neutral, Professional, Friendly, Casual), format (Plain text, Message,
  Email, Bullet list), length (Original, Concise). Neutral + Plain text +
  Original is *no rewrite* and never calls the model. The defaults and all
  built-in modes (Exact, Clean, Message) have no style.
- **Exact bypass** — `DictationMode.effectiveStyle` is none when the writing mode
  is Exact; the editor disables the controls and clears them when Exact is
  chosen. Existing Exact, Clean, and personalization output is unchanged.
- **Migration** — `style` decodes with `decodeIfPresent`, so libraries, archives,
  and exports written before this change load with no style. The archive format
  stays version 1; older builds ignore the extra key.
- **Order** — recognise → write (Exact/Clean) → personalise → **rewrite** →
  context formatting and trailing space. Snippets are delivered as written and
  skip the rewrite.
- **Instruction wording** — fixed text built only from the enumerated choices
  (`StyleInstruction`), never from dictated words. The dictation is the fenced
  passage the rewriter already treats as data (ADR 0018). Dictation that looks
  like an instruction is rewritten as content.
- **Meaning check** — `PreservationChecker` (pure) rejects a result that drops,
  changes, or adds numbers, days/months/relative dates, names, negations,
  commitments (will, must, promise, might, …), links and email addresses, or
  that greets/signs with a name that was not said. It is deliberately
  conservative and cannot judge meaning in general; the preview covers the rest.
  Known gap: a name at the very start of a sentence is not tracked.
- **Review always** — a rewrite ends in a review with Insert, Use Original,
  Regenerate, Copy, and Discard; the original is one click away. Nothing is
  inserted or sent until the user chooses. Regenerate rewrites the same text
  again without recognising the audio again.
- **Failure** — unavailable, refused, too long, failed, or rejected rewrites
  keep the original, show why ("Not rewritten: …"), and never count as a
  successful rewrite. The pre-recording check does not refuse: the speech is
  still worth keeping.
- **Languages** — availability comes from the rewriter per language. For a
  language the model does not support the original is shown with the reason.
- **Privacy** — on device only; the review (rewrite and original) lives in the
  coordinator for the session and is cleared on Insert, Copy, Use Original,
  Discard, cancel, a new session, and the attention timeout. Diagnostics hold the
  style identifier, a flag, a notice identifier, and durations only.

## Evidence

On the development Mac (Apple Intelligence available), the opt-in test
`FoundationModelsStyleTests` ran all 31 style combinations on a synthetic
sentence in about 17 seconds (≈ 0.6 s each) and at least 90 % kept every name,
number, date, negation, and commitment. The first run (80 %) found that an
email instruction forbidding recipient names made the model drop a name that
was spoken; the wording now says to greet only by a name in the passage and to
write no subject line. This is one sentence on one Mac: it is evidence the path
works, not a quality approval.

## Risks and evidence still missing

- Quality on real dictation, many sentences, and several Macs; Foundation
  Models language coverage for Hindi and Telugu is not established (the
  rewriter reports `unsupportedLanguage` and the original is shown).
- Thresholds are Proposed (`docs/testing/style-rewriting.md`).
- iPhone and iPad cannot assume the host app is known (Epic 8).

## Consequences

- `DictationMode` gains `style`; `DictationOutcome` gains `.review`;
  `DictationIssue` gains `.reviewRewrite`; `DictationProcessing` gains
  `regenerate`.
- A rewrite adds roughly the model's latency (≈ 0.6 s measured) before the text
  appears, always followed by a click.
