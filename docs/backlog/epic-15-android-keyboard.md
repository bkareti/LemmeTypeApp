# Epic 15 — Android keyboard and cross-app dictation

## Epic issue body

### Objective

Let a user dictate straight into WhatsApp, Messages, Gmail, Chrome, and other apps with a
microphone key on the LemmeType keyboard, inserting text once into the field they were in,
with no Accessibility Service and nothing sent. **Starts only if E14-S3 is Demonstrated
on at least two vendors** ([plan](../android/android-plan.md) Phase 4, [ADR 0035](../decisions/0035-android-app.md)).

### Business value

Copy and paste is the main friction in mobile dictation. Android lets a keyboard know the
host app and insert text directly; if it can also record, LemmeType gets a one-tap flow that
iOS cannot match.

### In scope

- A decision record from the E14-S3 evidence.
- An `InputMethodService` with basic typing, a mic key, a recording strip, review chips.
- Recording inside the keyboard flow (design chosen by E15-S1), the same pipeline as Quick Dictation.
- Insertion through `commitText` only into the field that was active when recording started.
- Password fields and sensitive apps refused; per-app modes from `EditorInfo.packageName`.
- A device validation matrix.

### Out of scope

- Autocorrect, next-word prediction, swipe typing, emoji search (LemmeType is a voice keyboard first; users can switch back to their usual keyboard).
- Reading text around the cursor (context formatting is E16-S3, off by default).
- Voice editing of a selection (deferred).
- Any network access from the keyboard.

### Epic acceptance criteria

- All child stories are accepted.
- The keyboard requests no permission beyond the app's own (`RECORD_AUDIO`, notifications, FGS); the manifest check enforces it.
- No text is ever inserted into a field other than the one active at start (tests + device matrix).
- The microphone indicator and a LemmeType recording state are visible whenever audio is captured.
- Quick Dictation remains available and works when the keyboard is not enabled.

---

## E15-S1 — Record the keyboard decision

**Objective:** turn the E14-S3 evidence into an approved design.

**User story**

As the maintainer, I want the keyboard design written down with its evidence so that the
build stories do not guess.

**Scope**

- Update ADR 0035 (keyboard line → Accepted or Rejected) or add a new ADR if the design is large.
- Choose: record in the input method, or start a `microphone` service from it; session length limit; what happens when the keyboard hides mid-recording; the review rule (Exact/Clean insert directly; rewrite and translation need a chip tap).
- List the manifest entries and their check allowlist lines.

**Acceptance criteria**

- Each choice cites a row in `docs/testing/android-feasibility.md`.
- If rejected: Epic 15 is closed and the plan's parity matrix says so.

**Dependencies:** E14-S3  
**Automated verification:** `make docs-check` passes.  
**Physical-device verification:** none new.  
**Estimate:** 2 points (Small)

---

## E15-S2 — Build the keyboard shell with basic typing

**Objective:** a keyboard people can leave enabled, so dictation is always one tap away.

**User story**

As a user, I want a simple keyboard that types letters, numbers, and punctuation, with a
microphone key and a way to switch to my usual keyboard.

**Scope**

- `LemmeTypeInputMethodService` (protected by `BIND_INPUT_METHOD`), `method.xml` with an English subtype, `supportsSwitchingToNextInputMethod`.
- `feature-keyboard-ui` (Compose in the IME window): QWERTY, symbols, numbers by `inputType` class, shift, delete with repeat, enter by `imeOptions` action, switch-keyboard key.
- Setup screen in the app: enable the keyboard in Settings, pick it, with plain-language explanation of what Android's warning means and what LemmeType does not do.
- Releases memory when hidden for a few seconds (Android guidance).

**Acceptance criteria**

- Typing works in a plain `EditText` and in Chrome (instrumentation test with a test activity; device check in Chrome).
- Number and phone fields show the right layout (test with `EditorInfo` fixtures).
- Switch key follows `shouldOfferSwitchingToNextInputMethod` (test).
- TalkBack reads every key.

**Dependencies:** E15-S1, E14-S6  
**Automated verification:** instrumentation tests with a host test activity.  
**Physical-device verification:** type a synthetic sentence in WhatsApp, Gmail, Chrome on two phones.  
**Estimate:** 8 points (Large)

---

## E15-S3 — Record from the keyboard mic key

**Objective:** tap, speak, tap — with the microphone visibly on only in between.

**User story**

As a user, I want to tap the mic key, talk, and tap again, and see a clear recording state
the whole time.

**Scope**

- Mic key → the recording design from E15-S1 → same `AudioCaptureService`, pipeline, and `RecordingLimits`.
- Recording strip replaces the keys: waveform, timer, mode name, Stop, Cancel.
- First use without `RECORD_AUDIO`: the key opens the app's permission screen (an activity), never a silent failure.
- Keyboard hidden or field lost mid-recording → follow the E15-S1 rule (stop and hold result for review, or cancel).
- Model not installed → a message with "Open LemmeType" to get it.

**Acceptance criteria**

- Tap-to-recording ≤ 500 ms (95th percentile) on the reference phone (device test).
- Every ending leaves no audio (tests with fakes).
- Recording never starts without a user tap (test).
- Password field: mic key hidden (test with `EditorInfo` fixtures).

**Dependencies:** E15-S2, E14-S11, E14-S12  
**Automated verification:** JVM tests of the keyboard view model; instrumentation tests with a fake source.  
**Physical-device verification:** 20 dictations across 3 apps; indicator visible each time.  
**Estimate:** 8 points (Large)

---

## E15-S4 — Insert once, only into the right field

**Objective:** the text lands exactly once, where the user started.

**User story**

As a user, I want the dictated text to appear in the message I was writing — and never in
another chat or field.

**Scope**

- Target capture at start: `EditorInfo.packageName`, `fieldId`, `inputType`, and a counter that increases on every `onStartInput`.
- On result: insert with one `commitText` (plus a trailing space by mode) only if the same target is active; otherwise keep the text in the strip with Insert and Copy, expiring after 2 minutes.
- Rewritten or translated text: review chips (Insert, Original, Discard), never auto-insert.
- No `InputConnection` read of field text in this story.

**Acceptance criteria**

- Field switch, app switch, and keyboard re-open each prevent automatic insertion (tests with a fake `InputConnection`).
- `commitText` is called at most once per result (test).
- A held result expires and is cleared from memory (test with `FakeClock`).

**Dependencies:** E15-S3  
**Automated verification:** JVM tests with fakes; instrumentation test with two fields in a test activity.  
**Physical-device verification:** switch chats in WhatsApp mid-dictation; nothing lands in the second chat.  
**Estimate:** 5 points (Medium)

---

## E15-S5 — Per-app modes and sensitive apps

**Objective:** use Android's knowledge of the host app for convenience and safety.

**User story**

As a user, I want Clean mode in Gmail and Message mode in WhatsApp automatically, and I
never want the mic key in my banking or password apps.

**Scope**

- `ModeResolver` app rules keyed by package name (from E16-S1; this story can ship with built-ins only).
- Built-in sensitive list (password managers, common banking apps in the matrix) + user exclusions in Settings.
- `IME_FLAG_NO_PERSONALIZED_LEARNING`: dictation allowed, nothing learned or remembered.

**Acceptance criteria**

- Excluded packages hide the mic key (test).
- App rule picks the mode at recording start and it does not change mid-session (test).
- The exclusion list is stored owner-only and removed by Delete All (test).

**Dependencies:** E15-S4, E16-S1 (for custom rules)  
**Automated verification:** JVM tests.  
**Physical-device verification:** one excluded app and one rule app on a phone.  
**Estimate:** 3 points (Small)

---

## E15-S6 — Validate the keyboard across apps and phones

**Objective:** evidence before we tell anyone the keyboard works.

**User story**

As the product owner, I want the keyboard checked in the apps and phones our users have so
that store text promises only what was shown.

**Scope**

- Host matrix: WhatsApp, Google Messages, Samsung Messages, Gmail, Chrome (textarea, `contenteditable`), Keep, one banking app, a work profile with a keyboard restriction.
- Phone matrix from plan section 11; Android 12, 14, 16/17.
- Vendor battery managers: recording for 60 s with the screen on; keyboard process killed and restarted.
- Accessibility: TalkBack, large font, dark mode.
- Manual acceptance steps (next free `MA-` numbers).

**Acceptance criteria**

- Matrix complete in `docs/testing/android-feasibility.md`; every failure has a fallback documented.
- Zero wrong-field insertions in the run.
- Tap-to-recording and stop-to-text within the approved thresholds.

**Dependencies:** E15-S2 … E15-S5  
**Automated verification:** the instrumentation suite green on API 31 and 36.  
**Physical-device verification:** the matrix.  
**Estimate:** 5 points (Medium)

---

## Epic 15 story order

1. E15-S1
2. E15-S2
3. E15-S3
4. E15-S4
5. E15-S5
6. E15-S6
