# Readiness review — Epic 3 (context-aware writing and voice editing)

Reviewed 2026-10-17 with the `story-review` skill against
`docs/backlog/epic-03-context-aware-writing.md`, the Epic 2 code on `main`,
ADRs 0001–0016, and the macOS 26 / Xcode 27 SDK.

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E3-S1 Context model & policy | Ready | Pure Domain. Narrows ADR 0015's "never read text" rule → ADR 0017. |
| E3-S2 Capture at activation | Ready with notes | Real reading needs other apps → manual matrix; logic runs on CI against the fake driver. |
| E3-S3 Context formatting | Ready | Pure Domain; fully testable on CI. Tone is out of scope. |
| E3-S4 Language-model contract | Ready with notes | New `Editing` module and first FoundationModels use → ADR 0018. Real model is manual-only. |
| E3-S5 Voice editing | Ready with notes | Second global shortcut; recorder gains an early "needs attention" path. |
| E3-S6 Context controls | Ready | — |
| E3-S7 Validation | Ready with notes | Latency threshold needs product-owner approval, like E2-S10. |

No blockers.

## Cross-cutting decisions (proposed defaults)

1. **What may be read** — at most 240 UTF-16 code units before the
   selection, 40 after it, and, for voice editing only, the selected text up to
   4,000 code units (longer selections are refused, not truncated, so an edit
   never silently drops text). Nothing else: no window titles, no other
   elements, no screen content. ADR 0017.
2. **When** — only inside the shortcut handler, right after the target is
   captured. Never while recording or processing, never in the background.
3. **Order of checks** — app policy (sensitive / excluded / switch) →
   Accessibility trust → element → password field (`AXSecureTextField`) →
   secure keyboard entry → selection. The secure check comes before any text
   attribute is read, as in ADR 0015.
4. **Reading API** — `kAXSelectedTextRangeAttribute` for the range and
   `kAXStringForRangeParameterizedAttribute` for bounded text, through new
   `AccessibilityDriving.text(in:of:)`. The capture logic is a generic
   `CursorContextReader<Driver>` in Domain so CI tests it with
   `FakeAccessibilityDriver`. The app's Accessibility permission already
   covers this; no new TCC permission.
5. **Lifetime** — the context lives in `ActivationTarget.context`, which the
   session owns; it is dropped when the session ends. `CursorContext`
   redacts its `description`/`debugDescription`, so interpolation into a log
   or error cannot leak it. Diagnostics get the purpose and an outcome
   identifier only (no lengths of other apps' text).
6. **Defaults** — formatting context **off** (privacy-first, opt-in in
   Settings › Context); voice editing **on** (it reads only the selection and
   only when its shortcut is pressed). Built-in sensitive apps (password
   managers, Keychain Access, Passwords) can never be enabled.
7. **Formatting** — `ContextFormatter` (Domain, pure) runs after the writing
   mode. Exact: spacing only. Clean: spacing, continuation case (a short list
   of common words only, so names are never lower-cased), mid-sentence period
   removal, and duplicate-punctuation removal. Each change is a
   `ContextTransformation` naming its `ContextRule`.
8. **Language model** — Apple Foundation Models `SystemLanguageModel`
   (on device, part of macOS 26, no download or third-party code) with
   `Guardrails.permissiveContentTransformations`, greedy sampling, and a new
   `LanguageModelSession` per request so no transcript is retained.
   `PrivateCloudComputeLanguageModel` is never used. New `Editing` module
   (Domain + Support + FoundationModels). ADR 0018.
9. **Voice editing flow** — `ActivationController` owns a second shortcut
   (default ⌥⇧Space) and sends `.startEditing(target)`; one session at a
   time across both shortcuts. The pipeline recognises the instruction, runs
   the rewriter, and delivers through the existing `TextDelivering`, which
   now also refuses when the selection differs from the captured one
   (`targetChanged`). The recorder can go from *preparing* straight to
   *needs attention* so a missing selection or model is reported before the
   user speaks.

## Story notes

### E3-S1 — Context model & policy — Ready
| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | The privacy rule every later story relies on. |
| 2 | Size | Pass | 5 points. |
| 3 | Dependencies | Pass | E2-S7 merged (`AccessibilityDriving`, `ActivationTarget`). |
| 4 | Acceptance criteria | Pass | All unit-testable. |
| 5 | CI testability | Pass | Domain only. |
| 6 | Privacy | Pass | Redacted descriptions; preferences store identifiers only. |
| 7 | Permissions | Pass | None new. |
| 8 | Feasibility | Pass | — |
| 9 | Out of scope | Pass | Retention/history stays in Epic 6. |
| 10 | Open decisions | Concern | Default for formatting context: proposed **off**. |

### E3-S2 — Capture at activation — Ready with notes
| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | — |
| 2 | Size | Pass | 8 points. |
| 3 | Dependencies | Pass | E1-S4 target capture, E2-S7 driver. |
| 4 | Acceptance criteria | Pass | "Read once", "never while recording" are testable with the fake driver's read counters. |
| 5 | CI testability | Concern | Real apps differ in `AXStringForRange` support → insertion-matrix columns (E3-S7). |
| 6 | Privacy | Pass | Secure checks first; nothing logged. |
| 7 | Permissions | Pass | Accessibility (already granted for insertion). |
| 8 | Feasibility | Pass | Parameterized attributes exist on macOS 26; 0.25 s messaging timeout per call. |
| 9 | Out of scope | Pass | — |
| 10 | Open decisions | Concern | Capture runs on the main actor in the shortcut handler; worst case ≈1 s for a hung app (4 calls × 0.25 s), accepted and documented. |

### E3-S3 — Context formatting — Ready
- "Common words" list is version-controlled in Domain; anything not in it keeps
  its case, so "Paris", "Monday", and "iPhone" are safe.
- "Tone" from the roadmap description needs a language model and style controls;
  moved to Epic 4.

### E3-S4 — Language-model contract — Ready with notes
- Package tests use a fake; the real model is unavailable on the CI runner. The
  `Editing` module compiles on CI (the SDK has the framework) and its error
  mapping is unit-tested without calling the model.
- Network silence during rewriting is a manual step (MA, `nettop`).
- Prompt injection inside selected text can at worst change the rewrite of the
  user's own selection, which the user sees immediately and can undo; accepted.

### E3-S5 — Voice editing — Ready with notes
- Needs a new `ProcessingPhase.rewriting`, a `DictationIssue.editingUnavailable`
  family, and a recorder transition `preparing → needsAttention`.
- ⌥⇧Space passes `ShortcutValidation`; it is configurable and can be turned off.
- Undo relies on the target app's own Undo; recorded per app in the matrix.

### E3-S6 — Context controls — Ready
- Excluded apps are chosen from running regular apps (bundle identifier and name).

### E3-S7 — Validation — Ready with notes
- Threshold approval is a product-owner action outside the code.

## AC → verification map

| Acceptance criterion | Verification |
|---|---|
| S1 caps and over-long selection rejected | `CursorContextTests.capsAndRejectsLongSelections` |
| S1 description never reveals text | `CursorContextTests.descriptionIsRedacted` |
| S1 policy blocks by switch / excluded / sensitive | `ContextPolicyTests` |
| S1 stable identifiers | `ContextPolicyTests.reasonIdentifiersAreStable` |
| S1 preferences store switches and IDs only | `UserDefaultsPreferencesTests.contextPreferences` |
| S1 defaults | `UserDefaultsPreferencesTests.contextDefaults` |
| S2 bounded capture once | `CursorContextReaderTests.capturesBoundedWindowOnce` |
| S2 secure field / input never read | `CursorContextReaderTests.secureFieldIsNeverRead`, `…secureInputBlocks` |
| S2 excluded / sensitive app not read | `CursorContextReaderTests.excludedAppIsNeverRead` |
| S2 unreadable app proceeds | `CursorContextReaderTests.unreadableFieldProceedsWithoutContext` |
| S2 only at activation | `ActivationControllerTests.capturesContextOnlyOnStart` |
| S2 diagnostics identifiers only | `DiagnosticsPrivacyTests.contextNeverReachesDiagnostics` |
| S3 spacing / case / punctuation examples | `ContextFormatterTests` (one test per example) |
| S3 Exact spacing only | `ContextFormatterTests.exactOnlyAdjustsSpacing` |
| S3 no context = Epic 2 output | `TranscriptionPipelineTests.withoutContextOutputIsUnchanged` |
| S3 rule named per change | `ContextFormatterTests.everyChangeNamesItsRule` |
| S4 availability states | `FoundationModelsRewriterTests.mapsAvailability` |
| S4 runner guarantees | `TextRewritingRunnerTests` + `TextRewriterContract` |
| S4 error mapping | `FoundationModelsRewriterTests.mapsGenerationErrors` |
| S4 nothing retained / network silent | Code review (session per request) + MA-40 |
| S5 replace selection once | `VoiceEditingPipelineTests.replacesSelectionOnce` |
| S5 refuses before recording | `RecordingCoordinatorEditingTests.blockedEditNeverRecords` |
| S5 changed selection | `AccessibilityInsertionTests.changedSelectionIsNotReplaced` |
| S5 refusal leaves original | `VoiceEditingPipelineTests.refusalKeepsOriginal` |
| S5 diagnostics | `DiagnosticsPrivacyTests.editingNeverReachesDiagnostics` |
| S6 pane, switch, exclusions | `ContextSettingsModelTests` + MA-43 |
| S6 overlay / VoiceOver | `RecordingCoordinatorEditingTests.reportsContextStatus` + MA-44 |
| S7 end-to-end and canaries | `ContextEndToEndTests` |
| S7 manual / matrix / threshold | `docs/testing/manual-acceptance.md`, `insertion-matrix.md`, `performance-thresholds.md` |
