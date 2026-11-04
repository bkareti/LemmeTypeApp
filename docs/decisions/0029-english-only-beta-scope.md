# 0029 — English-only scope for the friends beta

- Status: Accepted for the friends beta; revisit when a language pack is validated.
- Date: 2026-11-04
- Related: ADR 0023 (multilingual dictation), ADR 0028 (Whisper decoding safeguards),
  #135–#138, `docs/release/friends-beta-readiness.md`

## Context

The first friends beta must support English only. Everything else in it is
measured: English dictation has accepted benchmark results (E2-S10, E5-S7) and
the no-speech and loop safeguards (ADR 0028). Hindi is still `evaluation`, and
Telugu with Whisper Small is `unreliable` (#137, #138).

Epic 9 shipped Hindi and Telugu, Automatic detection, and translation to
English. Without a change, a tester sees them in Settings › Dictation, in the
mode editor, in the iPhone settings, and as three extra multilingual model
downloads (up to 852 MB). That contradicts "English only" and invites testers to
judge the beta on languages we already know are weak.

## Decision

`LanguageScope` (Domain) says which languages a build offers:

| Scope | Language menu | "Text you get" | Models listed |
|---|---|---|---|
| `englishOnly` | English (and the regions Apple Speech offers) | hidden: only Original | English-only Whisper Tiny/Base/Small |
| `allLanguages` | Automatic, English, Hindi, Telugu (with their status) | Original or English | all six |

- `DictationSettingsModel(languageScope:)` decides the language and output
  choices; `ModesSettingsModel(speechOutputs:)` and the composition roots pass
  them on. `ModelsSettingsModel` gets the catalog filtered with
  `LanguageScope.lists`.
- **Release builds are English only.** `Config/Release.xcconfig` adds the
  compilation condition `ENGLISH_ONLY_RELEASE`; `AppComposition.languageScope`
  and `IOSComposition.languageScope` read it. Debug builds keep every language,
  so evaluation (`make evaluation`, `make evaluation-ios`) and the UI tests are
  unchanged.
- The engines, model catalog, pipeline, and stored settings are untouched. A
  stored non-English language stays visible (the existing rule for a value that
  is no longer offered) so a person can switch back to English; fresh installs
  default to `en-US`.

## Extension point for language packs

Adding a language later is a scope change, not a rewrite:

1. Measure it with the corpus (`docs/testing/evaluation-harness.md`) until its
   `LanguageSupportMatrix` row is `validated`.
2. Widen the scope (a new case, or `allLanguages` filtered by the matrix) and
   remove or change `ENGLISH_ONLY_RELEASE`.
3. Nothing in the engines or the session model changes.

## Alternatives considered

| Option | Why not |
|---|---|
| Delete the multilingual code | Throws away measured work and the evaluation harness; the next release needs it. |
| A runtime switch in Settings | Testers would find it; and an English-only promise should not depend on a preference. |
| An Info.plist key | `GENERATE_INFOPLIST_FILE` cannot carry custom keys without a hand-kept plist; a compilation condition is one line. |
| Keep everything and label it | Already done (badges); it still offers 852 MB downloads and translation that the beta does not support. |

## Consequences

- A tester never sees Automatic, Hindi, Telugu, translation, or the multilingual
  models in a Release build.
- `make release-build` produces the English-only app; the maintainer's own
  Release builds are English only until the condition is removed.
- A multilingual model installed earlier still works and is still removed by
  **Delete All Local Data**; it is no longer listed in Settings › Models.
