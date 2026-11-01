# Epic 9 — multilingual dictation and speech-to-English translation

## Epic issue body

### Objective

Let a multilingual user speak in a supported language and receive either the
original-language text or English text in the active writing workflow, entirely
on this Mac.

### Business value

Many people think in one language and write in another, or mix two in one
sentence. English-only dictation makes them type. Local speech-to-English and
original-language dictation remove that step without sending audio anywhere.

### In scope

- Evaluating Telugu, Hindi, and English (plus Telugu–English and Hindi–English
  mixed speech) and publishing a support matrix of measured results only.
- Multilingual Whisper models in the verified model catalog, and a
  language-aware recognition contract (language, task, automatic detection).
- Source language (manual, or Automatic where detection is validated) chosen
  independently from the output: original language or English.
- Readiness shown before recording: resolved language, output, model state, and
  unavailable combinations.
- A translation preview with retry and cancel; delivery only on an explicit action.
- Privacy, quality, and performance validation, and thresholds for approval.

### Out of scope

- Cloud, Private Cloud Compute, or any network fallback.
- Translating typed or selected text (Epic 3 covers selected-text editing).
- Output languages other than the original or English.
- Languages beyond the evaluation set (Tamil, Malayalam, and Kannada are the
  next candidates and are not selectable until evaluated).
- iPhone and iPad (Epic 8, #84, #85); mobile reuses these contracts later.
- Language-specific Clean Writing rules (non-English text is written Exact).

### Epic acceptance criteria

- All child stories are accepted.
- A tested support matrix lists each language, engine, task, and status; no
  language is called Validated without an approved measurement.
- Source language and output are chosen separately; Exact Dictation never
  translates or rewrites.
- Translation runs locally, is previewed, and is delivered only on request.
- Missing models, unsupported combinations, cancellation, and memory pressure
  leave the destination untouched and delete temporary audio and text.
- Quality, latency, and memory thresholds are approved before acceptance.

---

## E9-S1 — Decide the language, engine, and model matrix

**User story**

As a product team, we want a recorded decision and a tested support matrix so
that we promise only the languages we have measured.

**Scope**

- ADR 0023: use the existing whisper.cpp runtime with its multilingual models
  (Tiny, Base, Small), Whisper's built-in speech-to-English task for
  translation, and Apple Speech unchanged (English only). Record why a cloud
  service, a separate translation model, and Apple's Translation framework were
  not chosen.
- `SpokenLanguages` and `LanguageSupportMatrix` (Domain): language, engine, task,
  smallest model tier, hardware, and status (`evaluation` or `validated`).
- `docs/testing/language-support-matrix.md` explains the statuses and lists
  the evaluation scenarios, including mixed-language speech.
- Proposed quality, latency, and memory thresholds, marked Proposed.

**Acceptance criteria**

- The initial matrix contains English, Hindi, and Telugu as `evaluation`; Tamil,
  Malayalam, and Kannada are absent from the selectable set (unit tests).
- Every matrix row names a model that exists in the catalog and an engine that
  declares the language and task (unit tests).
- No row is `validated` without a measurement record; a test fails if a row is
  promoted without one.
- The ADR lists decisions, alternatives, risks, and the evidence still missing.
- Thresholds are in the document with status Proposed.

**Dependencies:** E5-S1, ADR 0012, ADR 0022  
**Estimate:** 3 points

---

## E9-S2 — Add multilingual Whisper models and language-aware recognition

**User story**

As a multilingual user, I want LemmeType to recognise Hindi and Telugu with a
model I download and verify so that I can dictate in my language on this Mac.

**Scope**

- Catalog: Whisper Tiny, Base, and Small (multilingual) pinned by HTTPS URL,
  size, and SHA-256, with tasks and languages. English-only models are unchanged.
- `RecognitionTask` (transcribe, translate to English), `RecognitionRequest.task`,
  engine `tasks` and a language-detection capability, and
  `availability(for:)` so readiness depends on language and task.
- The Whisper engine picks an installed model that can serve the request:
  English-only models serve English transcription only; multilingual models
  serve everything.
- Automatic language detection among the evaluation languages. Detection below
  a confidence threshold, or a language outside the set, fails with
  `recognition.language-uncertain` instead of guessing English.
- whisper.cpp runtime: language, translate flag, and detection probabilities.

**Acceptance criteria**

- Each new catalog entry has source, size, SHA-256, licence, languages, tasks,
  memory estimate, tier, and hardware requirement (catalog tests).
- With only an English-only model installed, a Hindi or translate request is
  unsupported and loads nothing; with a multilingual model it runs with the
  requested language and task (engine tests with a fake runtime).
- English dictation still works with an installed English-only model, and with
  only a multilingual model installed.
- Automatic detection picks the most probable evaluation language above the
  threshold; below it, or with no candidate, it fails as language-uncertain and
  produces no transcript (engine tests).
- The engine contract tests pass unchanged: no network, cancellation, no retention.
- An existing Whisper Base (English) installation keeps working without a download.

**Dependencies:** E9-S1, E5-S1, E5-S3  
**Estimate:** 8 points

---

## E9-S3 — Choose the spoken language and output, and see readiness before recording

**User story**

As a multilingual user, I want to choose the language I speak and whether I get
original text or English, and see whether that works before I record, so that I
never speak into a combination that cannot run.

**Scope**

- `SpeechOutput` (original language, English) stored in preferences and, per
  mode, optionally in `DictationMode` next to the existing language override;
  existing saved libraries keep decoding.
- Language choice: the evaluation languages plus Automatic (Automatic only
  where detection is available).
- `LanguageReadiness` (Domain, pure): ready with the model that will run,
  model not installed (with its download size), unsupported on this Mac, no
  engine for the language, or output not possible for the language.
- Settings › Dictation: language and output pickers, a readiness line, and a
  link to Models; the status menu shows the resolved language and output.
- The recorder refuses before the microphone starts when the combination
  cannot run, with a message and Open Models; nothing is inserted.

**Acceptance criteria**

- Language and output are independent choices (unit and view-model tests).
- Readiness covers each outcome above with the exact reason (unit tests).
- Selecting Hindi with only English models installed shows "needs download" and
  recording is refused before the microphone starts (coordinator test).
- Automatic is not offered when no installed engine can detect languages.
- Old preference and library data decode with output `original` (migration test).
- Existing English settings and modes behave exactly as before.

**Dependencies:** E9-S2, E4-S5  
**Estimate:** 5 points

---

## E9-S4 — Translate speech to English and write non-English text safely

**User story**

As a multilingual user, I want my speech turned into English text, or kept in my
language, without the app changing my words in ways it should not.

**Scope**

- The session captures language and output; the pipeline requests the
  translation task only when the output is English and the language is not
  English.
- Non-English original-language text is written Exact (spacing only): Clean
  Writing, context formatting, and the final-period style are English rules and
  are skipped. Personalization and snippets still apply.
- Translated English text goes through the mode's normal writing steps.
- Diagnostics record language, task, and output identifiers only.

**Acceptance criteria**

- Output Original never requests translation, in any writing mode (test).
- Output English with Hindi speech requests translation; English speech with
  output English is transcribed normally (pipeline tests).
- Hindi/Telugu text is not altered by Clean Writing, formatting, or final-period
  rules; numbers, names, and scripts are untouched (tests with Devanagari and
  Telugu script).
- Translated text receives the mode's Clean Writing.
- Diagnostics contain no text and no device or app names (privacy canary).

**Dependencies:** E9-S2, E9-S3  
**Estimate:** 8 points

---

## E9-S5 — Preview translated text and deliver only on request

**User story**

As a user, I want to read the English translation before it goes anywhere so
that a wrong translation never lands in a message or document.

**Scope**

- A translated result is shown in the overlay with Insert, Copy, Translate
  Again, and Discard. Nothing is inserted until the user chooses Insert or Copy.
- Insert uses the normal delivery path, including target validation and the
  clipboard policy; nothing is ever sent.
- The preview and its audio are held in memory and temporary storage only, and
  are deleted on Discard, Insert, Copy, cancel, timeout, and the next session.

**Acceptance criteria**

- A translation produces a review state and no delivery call (pipeline test).
- Insert delivers once; Copy puts the text on the clipboard; Translate Again
  re-runs the same recording; Discard deletes the audio and text (coordinator tests).
- If the target field changed during the review, Insert refuses and offers Copy.
- The preview text is never logged or placed in diagnostics (canary test).
- The overlay announces the review state to VoiceOver and every action has a
  label and identifier.

**Dependencies:** E9-S4, E2-S7  
**Estimate:** 5 points

---

## E9-S6 — Validate multilingual dictation: privacy, quality, and performance

**User story**

As a product team, we want evidence that multilingual dictation is private, keeps
meaning, and is fast enough so that we can decide what to call supported.

**Scope**

- End-to-end tests with fakes at the OS edges for: Hindi original, Telugu
  original, Hindi to English with preview, Automatic with uncertain detection
  then manual choice, missing model, cancellation, and memory pressure.
- A synthetic bilingual corpus specification, a human review rubric (meaning,
  names, numbers, dates, negation, intent), and the threshold document.
- The benchmark can run a language and task; the network monitor covers
  recording, recognition, translation, and delivery.
- Manual acceptance steps for real models and real speech.

**Acceptance criteria**

- Each scenario above has an end-to-end test; failures leave the destination
  untouched and delete temporary audio.
- Canary tests show no spoken or translated text in logs, diagnostics, or errors.
- The corpus specification states licence and consent rules; the rubric defines
  a pass for each preservation category.
- Proposed thresholds exist for each language: quality score, real-time factor,
  and memory. Acceptance of Epic 9 needs them approved.
- The manual checklist covers download, offline operation, accent and mixed
  speech, and results recorded in the support matrix.

**Dependencies:** E9-S1 through E9-S5, E6 privacy validation where available  
**Estimate:** 5 points

## Epic 9 story order

1. E9-S1
2. E9-S2
3. E9-S3
4. E9-S4
5. E9-S5
6. E9-S6
