# Epic 2 — local transcription, cleanup, and text delivery

## Epic issue body

### Objective

Convert an Epic 1 recording into useful text entirely on the Mac, offer explicit
Exact and Clean modes, and return the result safely to the field that was active
when the recording began.

### Business value

This epic completes the first end-to-end product promise: press a shortcut,
speak, and receive clean text anywhere without uploading the recording.

### In scope

- A recognition-engine abstraction.
- Apple Speech recognition.
- One optional downloadable local model.
- Verified model installation.
- Transcription orchestration and cancellation.
- Exact Dictation and deterministic Clean Writing modes.
- Accessibility insertion and clipboard fallback.
- Compatibility, privacy, performance, and end-to-end acceptance tests.

### Out of scope

- Generative reply drafting.
- Reading surrounding cursor or screen context.
- Local language-model rewriting.
- Cloud recognition or enhancement.
- Multiple downloadable model families.

### Epic acceptance criteria

- All child stories are accepted.
- A clean supported Mac can complete first dictation with Apple Speech or the optional local model.
- The normal workflow functions without network access after required assets are installed.
- Exact Dictation and Clean Writing are visibly distinct and testably preserve meaning.
- Delivery works in the supported app matrix with a recoverable fallback.
- Temporary audio is removed according to the documented lifecycle.

---

## E2-S1 — Define the local recognition-engine contract

**User story**

As a developer, I want speech engines behind one contract so that LemmeType can
change or add local providers without coupling them to recording and UI code.

**Scope**

- Define engine identity, availability, supported languages, asset requirements, and capability metadata.
- Define streaming/batch input, partial/final transcript output, cancellation, progress, and typed errors.
- Define transcript segments and confidence metadata without leaking provider-specific objects.
- Provide a deterministic fake engine for tests.
- Document that local engines must not initiate network requests during recognition.

**Acceptance criteria**

- The coordinator can execute a fake engine without importing a concrete recognition framework.
- Engine availability distinguishes ready, assets missing, unsupported hardware/OS, permission unavailable, and failed states.
- Cancellation has defined behavior and cannot emit a successful final result afterward.
- Transcript models represent final text, optional segments, timing, confidence, engine, language, and duration.
- Contract tests are reusable by every concrete engine.

**Dependencies:** Epic 1, E1-S5  
**Estimate:** 5 points

---

## E2-S2 — Implement the Apple Speech recognition engine

**User story**

As a user, I want a lightweight recognition option that uses Apple-provided
assets so that I can dictate without downloading a large third-party model.

**Scope**

- Implement Apple Speech behind the E2-S1 contract.
- Request and represent any recognition authorization separately from Microphone permission.
- Prefer on-device recognition and report when it is not available.
- Support English MVP locale selection.
- Produce partial results when supported and one final transcript.

**Acceptance criteria**

- Given the selected locale supports on-device recognition and assets are ready, then recognition completes with no application-initiated network request.
- Given on-device recognition is unavailable, then the engine reports Unavailable and never silently falls back to network processing.
- Given authorization is denied, then the app shows a recovery path without losing the recorded audio until the retry/cancel decision is made.
- Given cancellation, then the recognition task and related audio processing stop promptly.
- Contract tests pass and integration tests cover empty audio, silence, normal speech, cancellation, and framework error mapping.

**Dependencies:** E2-S1, E1-S3  
**Estimate:** 8 points

---

## E2-S3 — Integrate one downloadable local speech model

**User story**

As a privacy-focused user, I want a predictable offline recognition engine so
that dictation remains available even when Apple Speech is unsupported or unsuitable.

**Scope**

- Select and document one MVP model/runtime based on license, English accuracy, latency, memory, download size, and maintenance risk.
- Implement it behind the E2-S1 contract.
- Support model warm-up, inference, cancellation, and unload.
- Expose hardware/OS compatibility before download.
- Include required third-party notices.

**Acceptance criteria**

- The selection decision includes reproducible benchmark inputs and license review.
- Given installed assets and no network, then a recorded English utterance produces a final transcript.
- Given unsupported hardware or insufficient memory, then the model is not offered and the app explains why.
- Given cancellation during warm-up or inference, then processing stops and memory is released.
- The runtime does not retain audio or transcript after the session owner releases it.
- Contract tests pass for the engine.

**Dependencies:** E2-S1, E2-S4  
**Estimate:** 13 points

---

## E2-S4 — Download, verify, and remove local model assets

**User story**

As a user, I want model downloads to show their cost and verify their integrity
so that I can make an informed choice and trust the code and data running locally.

**Scope**

- Display model size, installed size, language, recommended hardware, and license.
- Download with progress, pause/cancel where supported, and safe retry.
- Stage downloads separately from active assets.
- Verify an allowlisted version and cryptographic digest before activation.
- Detect available disk space and clean partial downloads.
- Remove installed assets without affecting user settings.

**Acceptance criteria**

- The app requires explicit confirmation before downloading and shows expected storage usage.
- An interrupted download resumes safely or restarts without treating partial assets as installed.
- A digest mismatch prevents activation, deletes or quarantines invalid assets, and displays a recoverable error.
- Given insufficient storage, then download does not start and the required free space is shown.
- Removing a model frees its managed files and causes dependent modes to select a documented fallback or become unavailable.
- Model sources and hashes are version-controlled metadata, not accepted dynamically from untrusted input.

**Dependencies:** E1-S2, E1-S7  
**Estimate:** 8 points

---

## E2-S5 — Coordinate recording-to-transcript processing

**User story**

As a user, I want LemmeType to process each recording exactly once and recover
cleanly from failures so that dictation feels dependable.

**Scope**

- Create a transcription session that owns target reference, audio, selected engine, mode, timing, and cleanup lifecycle.
- Connect Epic 1 recorder states to engine preparation, recognition, and completion.
- Prevent overlapping processing from corrupting target delivery.
- Support cancel and retry while the target is still valid.
- Delete temporary audio after success/cancel based on the no-history default.

**Acceptance criteria**

- One completed recording creates exactly one transcription session and at most one final result.
- Sessions are isolated; late callbacks from a cancelled session cannot update a later session.
- Given recognition fails, then the user can retry with the same engine, choose an available engine, copy retained audio intentionally, or discard it.
- Given success and history disabled, then temporary audio is deleted after delivery completes.
- App quit, sleep, and crash-recovery paths never leave a session marked as actively recording.
- Session metrics contain duration and error category but not audio or text.

**Dependencies:** E2-S1, E1-S6, E1-S7  
**Estimate:** 8 points

---

## E2-S6 — Provide Exact Dictation and deterministic Clean Writing

**User story**

As a user, I want to choose between faithful transcription and conservative
cleanup so that LemmeType never rewrites my meaning without my knowledge.

**Scope**

- Exact Dictation mode that performs only documented normalization required for delivery.
- Clean Writing rules for capitalization, terminal punctuation, repeated filler words, spoken punctuation, and obvious immediate self-corrections.
- Rule-by-rule configuration model suitable for later settings UI.
- Before/after test corpus covering normal, technical, numeric, URL, email, and code-like text.

**Acceptance criteria**

- The active mode is visible before recording and stored with session metadata.
- Exact Dictation does not paraphrase, summarize, change tone, or remove meaningful words.
- Clean Writing transformations are deterministic for the same input and configuration.
- A cleanup rule never changes recognized numbers, URLs, email addresses, identifiers, or quoted content unless that rule explicitly supports and tests it.
- Self-correction removal handles defined patterns such as “Tuesday—sorry—Wednesday” and leaves ambiguous cases unchanged.
- Unit tests identify which rule produced every transformation.

**Dependencies:** E2-S5  
**Estimate:** 8 points

---

## E2-S7 — Insert final text through macOS Accessibility

**User story**

As a user, I want the final transcript inserted into the field where dictation
started so that I do not have to switch applications or paste manually.

**Scope**

- Resolve the target captured at shortcut activation.
- Validate that the target remains editable and is not a secure field.
- Replace an active selection or insert at the caret where supported.
- Preserve focus and provide typed outcomes: inserted, target changed, unsupported, permission missing, secure field, and failed.
- Establish a supported-app MVP matrix.

**Acceptance criteria**

- Given a supported editable field remains valid, when processing completes, then text is inserted once at the expected selection/caret.
- Given selected text existed at activation and the target still matches, then insertion replaces that selection.
- Given the active target changes during processing, then LemmeType does not insert into the new field silently and offers Copy or Retry Target.
- Secure/password fields are never read and receive no intelligent/contextual processing.
- Accessibility failure never causes partial duplicate insertion.
- Integration results are recorded for Mail, Messages, Notes, Safari text areas, one Chromium browser, Microsoft Word, Slack, and one code editor.

**Dependencies:** E2-S5, E2-S6, E1-S3, E1-S4  
**Estimate:** 13 points

---

## E2-S8 — Add clipboard fallback with restoration

**User story**

As a user, I want a safe fallback when direct insertion is unsupported so that
I can still use my transcript without losing clipboard contents.

**Scope**

- Snapshot supported clipboard item types before fallback.
- Put final text on the clipboard and invoke paste only after explicit or configured fallback behavior.
- Restore the previous clipboard after the target consumes the text, with configurable timing.
- Avoid overwriting a clipboard change made by the user during the operation.
- Provide Copy Only when automatic paste is unsafe.

**Acceptance criteria**

- Given direct insertion is unsupported and fallback is enabled, then final text is pasted once or copied with clear instructions.
- Plain text, rich text, images, and file URLs in the pre-existing clipboard are preserved for supported restoration types.
- If the clipboard changes after LemmeType writes its temporary value, LemmeType does not overwrite the newer user value during restoration.
- A failed or timed-out paste leaves the final transcript recoverable in the result UI.
- Clipboard contents never appear in logs, analytics, or diagnostics.
- Automated tests cover successful paste, slow target, timeout, user clipboard race, and unsupported clipboard types.

**Dependencies:** E2-S7  
**Estimate:** 8 points

---

## E2-S9 — Create the engine and mode selection experience

**User story**

As a user, I want to understand which local engine and writing mode are active
so that I can balance download size, speed, accuracy, and rewriting behavior.

**Scope**

- Settings UI for recognition engine, language, Exact/Clean mode, and optional model installation.
- Automatic recommendation based on availability without hidden cloud fallback.
- Menu-bar visibility of current mode and local/offline state.
- Clear blocked states when assets or permissions are missing.

**Acceptance criteria**

- Every selectable engine displays readiness, processing location, supported language, and required download.
- Automatic mode chooses only an available local engine and explains the current choice.
- Changing the engine affects the next session and never mutates an in-progress session.
- If a selected engine becomes unavailable, the app asks before changing it or uses a previously approved automatic policy.
- Exact versus Clean behavior is described in plain language before selection.

**Dependencies:** E2-S2, E2-S3, E2-S4, E2-S6  
**Estimate:** 5 points

---

## E2-S10 — Validate end-to-end privacy, performance, and compatibility

**User story**

As a product team, we want measurable acceptance evidence for the complete local
dictation loop so that the MVP is judged by user experience rather than isolated components.

**Scope**

- End-to-end tests from recorded fixture to delivered text.
- Offline/network-silence verification after asset installation.
- Latency and peak-memory benchmarks on minimum and recommended hardware.
- Accuracy corpus for conversational, accented, technical, numeric, and noisy speech.
- Supported-application insertion matrix and failure evidence.
- Manual acceptance run for a clean user account.

**Acceptance criteria**

- The test suite exercises Apple Speech and the downloadable engine using the same versioned audio corpus where licensing permits.
- A network monitor test confirms no application connection is initiated during local capture, recognition, cleanup, or delivery.
- Benchmarks report capture-stop-to-insertion latency, model warm-up, inference duration, peak memory, and audio duration without storing dictated user content.
- Product owners approve documented thresholds before the epic closes; regressions beyond the threshold fail the release check.
- Every unsupported application behavior has a safe fallback and no data loss.
- Temporary test recordings and generated transcripts are removed from release artifacts.

**Dependencies:** E2-S1 through E2-S9  
**Estimate:** 8 points

## Epic 2 story order

1. E2-S1
2. E2-S2 and E2-S4
3. E2-S3 and E2-S5
4. E2-S6
5. E2-S7 and E2-S8
6. E2-S9
7. E2-S10
