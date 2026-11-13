# Epic 16 — Android modes, personalization, rewriting, and model management

## Epic issue body

### Objective

Bring the Mac and iPhone writing features to Android using the same formats and rules:
modes, vocabulary, replacements, snippets, optional context formatting, optional on-device
rewriting, and model management that respects memory, heat, and battery
([plan](../android/android-plan.md) Phase 5).

### Business value

These features are what make LemmeType write "what you mean" rather than "what you said".
Using the Apple formats means a user can move their vocabulary and snippets from a Mac to an
Android phone.

### In scope

- Built-in and custom modes, app rules, the mode picker.
- Personalization library, owner-only storage, import and export of the existing archive format.
- Context formatting from text before the cursor (keyboard only), off by default.
- Rewriting with ML Kit GenAI (Gemini Nano) where available, with the preservation check and review.
- Model residency (idle unload, memory pressure, thermal, Battery Saver) and performance profile.
- Privacy overview and Delete All Local Data.

### Out of scope

- A LemmeType-owned rewriting model (needs its own ADR, as on iOS).
- Voice editing of a selection, history, sync of any kind.

### Epic acceptance criteria

- All child stories are accepted.
- Shared fixtures (modes, archive, cleanup) pass on Swift and Kotlin.
- A Mac personalization export imports on Android with the same entries.
- Rewriting is offered only where the device supports it; elsewhere the reason is shown.
- Delete All removes every LemmeType file and reports what it removed.

---

## E16-S1 — Modes and the mode picker

**Objective:** the same mode model as Apple (ADR 0021) on Android.

**User story**

As a user, I want to pick Exact, Clean, Message, or my own mode, and have apps use the mode
I set for them.

**Scope**

- `DictationMode` (engine, language, writing mode + rules, style, output, final period, trailing space), built-ins from `modes-builtin.json`, custom modes, `AppModeRule` by package name, `ModeResolver`.
- `SessionSettings` captured at recording start.
- Settings › Modes (Compose) and a picker on the Quick Dictation screen and the keyboard strip.

**Acceptance criteria**

- Built-ins equal the fixture (test).
- Resolver: app rule → default (test table mirrored from Swift).
- A mode change during recording affects only the next session (test).

**Dependencies:** E14-S14  
**Automated verification:** JVM tests; Compose UI test for the picker.  
**Physical-device verification:** none beyond smoke.  
**Estimate:** 5 points (Medium)

---

## E16-S2 — Vocabulary, replacements, snippets, and archive import

**Objective:** personalization with the Apple data format.

**User story**

As a user, I want my custom words, replacements, and snippets on my Android phone, and I
want to bring them from my Mac.

**Scope**

- `PersonalizationLibrary` with validation on every change; `Personalizer` (whole words, longest first, one pass); `SnippetMatcher` (whole utterance).
- Pipeline order as Apple: hints → snippets → writing mode → personalizer → context formatter.
- `FilePersonalizationStore`: versioned JSON, owner-only, atomic writes, unreadable or newer files moved aside.
- Import/export with the system file picker (Storage Access Framework); archive format equals the Apple one (fixture).

**Acceptance criteria**

- Synthetic archive fixture imports with the same counts and values (test).
- Export then import round-trips (test).
- A newer-version file is moved aside, never overwritten (test).
- No entry text appears in logs or diagnostics (canary).

**Dependencies:** E16-S1, E14-S7  
**Automated verification:** JVM tests; fixture parity.  
**Physical-device verification:** import a synthetic archive exported from the Mac app.  
**Estimate:** 5 points (Medium)

---

## E16-S3 — Context formatting in the keyboard (off by default)

**Objective:** match capitalization and spacing to the text already in the field, without keeping it.

**User story**

As a user who turns this on, I want dictated text to continue my sentence naturally — no
capital letter mid-sentence, no double space.

**Scope**

- `ContextFormatter` port (Exact: spacing only; Clean: continuation case, mid-sentence period, duplicate punctuation), each change a named transformation.
- Keyboard reads ≤ 240 characters before and ≤ 40 after the cursor with `getTextBeforeCursor`/`getTextAfterCursor` once, at recording start; never in password fields, excluded apps, or `NO_PERSONALIZED_LEARNING` fields.
- Setting off by default with a plain explanation.

**Acceptance criteria**

- Formatter fixture cases pass (shared fixture extended).
- Context is never read when the setting is off or the field is sensitive (tests with a fake `InputConnection` that fails on read).
- Context is dropped with the session and never logged (canary).

**Dependencies:** E15-S4, E14-S9  
**Automated verification:** JVM tests.  
**Physical-device verification:** WhatsApp and Gmail continuation on one phone.  
**Estimate:** 5 points (Medium)

---

## E16-S4 — Optional on-device rewriting

**Objective:** tone and style where the phone supports it, never pretending elsewhere.

**User story**

As a user with a supported phone, I want a professional or friendly version of what I said,
and the original one tap away.

**Scope**

- `rewriting-genai`: `TextRewriting` adapter over ML Kit GenAI (Rewriting API for fixed styles; Prompt API only if a style needs it), on-device only.
- Availability check with a reason (device not supported, model downloading, Battery Saver).
- `StyleInstruction` and `PreservationChecker` from Apple (shared fixture of style cases); a result that changes a fact is rejected.
- Always ends in review: Insert/Copy, Use Original, Regenerate, Discard.

**Acceptance criteria**

- Unsupported devices show "unavailable" with the reason (test with a fake).
- Preservation fixture cases pass (test).
- Exact mode never calls the rewriter (test).
- Real-model test is opt-in (`LEMMETYPE_REAL_REWRITE=1`), like Apple.

**Dependencies:** E16-S1, E14-S14  
**Automated verification:** JVM tests with `FakeTextRewriter`; contract test.  
**Physical-device verification:** a Gemini Nano phone (Pixel 9+ or Galaxy S25) and a phone without it.  
**Estimate:** 5 points (Medium)

---

## E16-S5 — Model residency, memory, heat, and battery

**Objective:** a loaded model when needed, nothing held when not.

**User story**

As a user, I want dictation to start fast and my phone not to slow down or heat up because
LemmeType kept a model in memory.

**Scope**

- `ModelResidencyController` port: warm while recording, unload after an idle period (default 3 min, Proposed) or on `onTrimMemory` critical/`onLowMemory`.
- `SystemConditionsMonitor`: `PowerManager` thermal status, Battery Saver, available memory.
- Performance profile (Automatic, Fastest, Most accurate) choosing model and threads.
- Refuse a load that does not fit, with the reason.

**Acceptance criteria**

- Idle unload and pressure unload tested with `FakeClock` and fake conditions.
- Severe thermal status picks the smaller model or warns (test).
- Memory above idle after unload returns to within 50 MB of baseline (device test).

**Dependencies:** E14-S12, E14-S13  
**Automated verification:** JVM tests.  
**Physical-device verification:** memory profile on two phones; 10 dictations in a row thermal check.  
**Estimate:** 5 points (Medium)

---

## E16-S6 — Privacy overview and Delete All Local Data

**Objective:** users can see and erase everything LemmeType keeps.

**User story**

As a user, I want one page that says what LemmeType stores, and one button that removes all of it.

**Scope**

- Privacy screen with plain-language text (shared with Apple `PrivacyText` where it applies; Android wording where it differs, for example "This app has no internet permission").
- Delete All: personalization, modes, exclusions, leftover sessions, diagnostics, models (asks), preferences; reports what was removed.
- Permission explanations (microphone, notifications, keyboard).

**Acceptance criteria**

- After Delete All, the app's files directory holds only what Android itself creates (test).
- Text passes the same reading checks as `PrivacyTextTests` (port).
- Removal of models asks first (test).

**Dependencies:** E16-S2, E14-S13  
**Automated verification:** JVM + instrumentation tests.  
**Physical-device verification:** Delete All on a phone, then check app storage in Android Settings.  
**Estimate:** 3 points (Small)

---

## Epic 16 story order

1. E16-S1
2. E16-S2
3. E16-S5
4. E16-S6
5. E16-S4
6. E16-S3
