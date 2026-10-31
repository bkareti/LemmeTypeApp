# Readiness review — Epic 9 (multilingual dictation and speech-to-English)

Reviewed 2026-10-31 with the `story-review` skill against
`docs/backlog/epic-09-multilingual-dictation.md`, issue #82, the code on
`main` (Whisper engine, catalog, pipeline, recorder), ADRs 0009–0022, and the
whisper.cpp v1.9.2 header (`translate`, `whisper_lang_auto_detect`).

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E9-S1 Matrix and ADR | Ready with notes | The spike cannot measure Telugu or Hindi quality without a licensed audio corpus; statuses start as `evaluation`. |
| E9-S2 Models and recognition | Ready with notes | Real-model behaviour is checked manually; CI uses a fake runtime. |
| E9-S3 Language and output controls | Ready | Reuses the mode language override and the editing pre-check pattern. |
| E9-S4 Translation pipeline | Ready | Whisper translates any language to English only. |
| E9-S5 Preview and delivery | Ready | Reuses the needs-your-decision overlay state. |
| E9-S6 Validation | Ready with notes | Threshold approval is a product-owner action. |

No blockers. Epic acceptance is blocked on threshold approval and real-speech
measurements, which are manual steps listed in `docs/testing/manual-acceptance.md`.

## Checklist (epic level)

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Speak in a supported language, get original or English text. |
| 2 | Size | Pass | Six stories, none above 8 points. |
| 3 | Dependencies | Pass | E5 (models), E2 (delivery), E4 (modes) are merged. |
| 4 | Acceptance criteria | Concern | Quality thresholds are "Proposed" until approved. |
| 5 | CI testability | Concern | Logic runs on fakes; real models and real speech are manual. |
| 6 | Privacy | Pass | Local only; the downloader is the single network path (ADR 0011). |
| 7 | Permissions | Pass | No new permission. |
| 8 | Feasibility | Pass | Multilingual `ggml-*.bin` models run on the same runtime. |
| 9 | Out of scope | Pass | Mobile, cloud, other output languages, typed-text translation. |
| 10 | Open decisions | Concern | See below. |

## Decisions to record (proposed defaults)

1. **Engine** — whisper.cpp multilingual models; Apple Speech stays English only.
2. **Translation** — Whisper's translate task (any language to English only).
   Apple's Translation framework is text to text, needs system language packs
   and a SwiftUI-owned session, and does not fit the headless pipeline; recorded
   as an alternative, not chosen.
3. **Models** — `ggml-tiny.bin`, `ggml-base.bin`, `ggml-small.bin` from
   `huggingface.co/ggerganov/whisper.cpp`, pinned by size and SHA-256 taken from
   the repository's LFS metadata (the same method reproduces the digests of the
   existing English models). Same allowlisted host; no new network code.
4. **Automatic detection** — limited to the evaluation languages, renormalised
   over them; confidence below 0.60 (Proposed) fails as language-uncertain and
   offers manual selection. English is never assumed.
5. **Non-English writing** — Exact only. The Clean Writing rules, context
   formatting, and final-period style are English.
6. **Review** — translated text is always previewed and delivered only on request.
7. **Status** — every language is `evaluation`; `validated` needs an approved
   measurement record.

## AC → verification map

| Acceptance area | Verification |
|---|---|
| Matrix, catalog pins, language/task support | `LanguageSupportMatrixTests`, `ModelCatalogTests` |
| Model selection by language and task, detection, uncertainty | `WhisperEngineLanguageTests` (fake runtime) |
| Independent language and output, readiness, refusal before recording | `LanguageReadinessTests`, `DictationSettingsModelTests`, `RecordingCoordinatorTests` |
| Old data decodes | `DictationModeTests` (stored sample) |
| Translation requested only when needed; non-English left Exact | `MultilingualPipelineTests` |
| Preview, Insert, Copy, Translate Again, Discard | `TranslationReviewTests`, `RecordingCoordinatorTests` |
| Privacy canaries | `MultilingualEndToEndTests`, `DiagnosticsPrivacyTests` |
| Real models, offline operation, accents, mixed speech | Manual acceptance, section "Multilingual dictation" |
