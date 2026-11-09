# 0023 — Multilingual dictation and speech-to-English translation

- Status: Accepted (languages are *evaluation* until measured; see below)
- Date: 2026-10-31
- Stories: E9-S1 … E9-S6 (issues #86–#91, epic #82)

## Context

Dictation so far recognises English. Multilingual users want to speak Hindi or
Telugu (alone or mixed with English) and get either that language's text or
English text. LemmeType's promise is that audio and text never leave the Mac, so
the answer has to run locally with models the app downloads, verifies, and
removes (ADR 0011, 0022).

## Decision

- **Engine and models** — keep the whisper.cpp runtime (ADR 0012) and add the
  multilingual `ggml-tiny.bin`, `ggml-base.bin`, and `ggml-small.bin` (MIT) to
  the catalog, pinned by size and SHA-256 from the same allowlisted host. The
  English-only models stay; an installed Base (English) keeps working. English
  uses an English-only model first and the multilingual model of any size
  otherwise. Hindi, Telugu, translation, and Automatic need a multilingual model.
- **Translation** — Whisper's built-in speech-to-English task
  (`translate = true`). It runs in the same pass as recognition, locally, and
  translates any supported language *to English only*. Other output languages
  are out of scope.
- **Apple Speech** — unchanged and English only. Its on-device language set
  has not been evaluated for these languages.
- **Language choice** — the setting stores `en-US` (as before), `hi`, `te`, or
  `auto`. Source language and output (`original` or `english`) are independent
  settings; a mode may override either, like the engine and language today.
- **Automatic detection** — whisper.cpp scores every language. LemmeType keeps
  only the evaluation languages. It fails with `recognition.language-uncertain`
  when those languages hold less than 50 % of the probability (the speech is
  probably another language), or when none has at least 60 % of that share.
  English is never assumed. The user then picks the language (Use English,
  Use Hindi, Use Telugu) and the same recording is processed again. Both
  numbers are **Proposed** until E9-S6 thresholds are approved.
- **Writing** — non-English original text is written *Exact* (spacing only):
  Clean Writing's fillers, capitalisation, and punctuation, the context
  formatter, and the final-period style are English rules. Personalization and
  snippets still apply. Translated English text goes through the mode's normal
  writing steps.
- **Review** — a translation is always previewed (Insert, Copy, Translate Again,
  Discard) and delivered only on request. It reuses the "needs your decision"
  overlay state; nothing is ever sent.
- **Readiness** — `LanguageReadiness` (Domain, pure) answers, before recording,
  whether the chosen language and output can run and what is missing. Recording
  is refused before the microphone starts when they cannot.
- **Support matrix** — `LanguageSupportMatrix` is the one source for what the
  app calls supported. English is `validated` (Epics 2 and 5). Hindi and Telugu
  are `evaluation`: selectable, labelled as such, and promoted only with a
  measurement record. Tamil, Malayalam, and Kannada are not selectable.

## Alternatives considered

| Option | Why not |
|---|---|
| Cloud speech or translation | Breaks the local-only promise. Reconsidered as an opt-in engine, off by default, in [ADR 0031](0031-cloud-speech-provider.md). |
| A separate translation model after transcription | Another download, runtime, and error path; Whisper already translates to English. |
| Apple's Translation framework | Text to text, needs system language packs and a SwiftUI-owned session; does not fit the headless pipeline. A later candidate for non-English output. |
| Apple Speech for Hindi | Not evaluated; on-device availability varies by Mac and OS. |
| Guess English when detection is unsure | Silently produces wrong text. |

## Risks and evidence still missing

- **Quality is unmeasured.** Whisper Tiny and Base are known to be weak on
  Hindi and Telugu; Small is recommended for evaluation. No result may be
  called a pass before the rubric in `docs/testing/language-support-matrix.md`
  is run on a licensed or consented corpus.
- **Mixed speech.** Telugu–English and Hindi–English sentences are decoded in
  the language chosen (or detected from the first 30 seconds). Whisper can drop
  or transliterate the other language; this is an evaluation scenario, not a
  promise.
- **Real runtime path.** Detection and translation call whisper.cpp directly.
  CI covers the logic with a fake runtime; the real-model behaviour is on the
  manual checklist (`docs/testing/manual-acceptance.md`).
- **Memory and latency** for Small on 8 GB Macs are Proposed thresholds.

## Consequences

- The catalog grows by three entries (about 713 MB if all are installed); the
  Models pane lists them with fit, size, and licence like the others.
- Engines gain `tasks`, a language-detection capability, and
  `availability(for:)`; existing engines keep their behaviour through defaults.
- A `RecognitionError.languageUncertain` and a `DictationAction.useLanguage`
  join the stable identifiers.
