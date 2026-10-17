# Epic 3 — context-aware writing and voice editing

## Epic issue body

### Objective

Use a small, deliberately captured piece of text around the cursor to make
dictated text fit where it lands (spacing, capitalization, punctuation), and let
users select text and speak an instruction to rewrite, shorten, format, or
translate it with an on-device language model.

### Business value

Dictation that ignores where it is inserted produces "Hello world." in the middle
of a sentence and forces manual fixes. Voice editing turns LemmeType from a
transcription tool into a writing tool, while keeping every word on the Mac.

### In scope

- A cursor-context model, privacy policy, and capture contract.
- Reading a bounded window of text around the caret, and the selected text,
  only when the user presses a LemmeType shortcut.
- Password fields, secure keyboard entry, built-in sensitive apps, and
  user-excluded apps never provide context.
- Deterministic context-aware spacing, capitalization, and punctuation.
- An on-device language-model contract and the Apple Foundation Models engine.
- A voice-editing shortcut that rewrites the selected text.
- Settings and overlay that show when context is used, with global and per-app controls.
- End-to-end, privacy, and compatibility validation.

### Out of scope

- Tone matching and reply drafting (needs style controls from Epic 4).
- Reading screen contents, other windows, or text beyond the bounded window.
- Continuous or background context monitoring.
- Downloadable or third-party language models (Epic 5).
- Cloud processing of any kind, including Private Cloud Compute.
- History of context or edits (Epic 6).

### Epic acceptance criteria

- All child stories are accepted.
- Cursor context is captured only while handling an explicit LemmeType shortcut press.
- Password fields, secure input, built-in sensitive apps, and configured apps are excluded.
- Context-aware formatting works without a language model.
- Selected-text editing works with the supported on-device language model.
- The user sees when context is used and can disable it globally or per app.

---

## E3-S1 — Define the cursor-context model and privacy policy

**User story**

As a privacy-conscious user, I want LemmeType to follow one clear rule about
when it may read text near my cursor so that context is never collected
silently or from sensitive places.

**Scope**

- Define `CursorContext`: bounded preceding text, following text, selection range,
  and optional selected text, in memory only, with redacted descriptions.
- Define the capture purposes (formatting, editing) and typed reasons context
  was not captured.
- Define `ContextPolicy`: a global switch for formatting context, a voice-editing
  switch, a user exclusion list, and a built-in sensitive-app list.
- Store the switches and exclusions in preferences (app identifiers only).
- Record the decision in an ADR that narrows ADR 0015's "never read text" rule.

**Acceptance criteria**

- `CursorContext` caps preceding text at 240, following text at 40, and selected
  text at 4,000 UTF-16 code units; longer selections are rejected, not truncated.
- Printing or interpolating a `CursorContext` never reveals its text.
- The policy blocks formatting context when the global switch is off, and blocks
  every purpose for excluded and built-in sensitive apps.
- Every "not captured" outcome has a stable lowercase identifier for diagnostics.
- Preferences persist only switches and bundle identifiers, never captured text.
- Formatting context is off by default; voice editing is on by default because it
  reads nothing until its shortcut is pressed.

**Dependencies:** E2-S7  
**Estimate:** 5 points

---

## E3-S2 — Capture cursor context through Accessibility at activation

**User story**

As a user, I want LemmeType to look at the text next to my cursor only at the
moment I press the shortcut so that it can fit my dictation in without watching
what I type.

**Scope**

- Read the selection range, a bounded window before and after it, and (for
  editing) the selected text, through Accessibility parameterized attributes.
- Capture during shortcut handling only, after the target is captured, and store
  it with the activation target and session.
- Check the policy, Accessibility trust, password fields, and secure keyboard
  entry before reading anything.
- Release the context when the session ends; never log, persist, or put it in diagnostics.

**Acceptance criteria**

- Given context is allowed and the field exposes text, when the shortcut is
  pressed, then the bounded preceding and following text is captured once.
- Given a password field or secure keyboard entry, then no text attribute is read
  and the reason is `secure-field` or `secure-input`.
- Given an excluded or sensitive app, then nothing is read from its elements.
- Given an app that does not expose text ranges, then dictation proceeds without
  context and the reason is `unreadable`.
- No context is read while recording, processing, or idle — only at activation.
- Diagnostics record the capture purpose and outcome identifier only.

**Dependencies:** E3-S1, E1-S4  
**Estimate:** 8 points

---

## E3-S3 — Format dictated text to fit the surrounding text

**User story**

As a user, I want dictated text to join the existing sentence naturally so that
I don't have to fix spaces, capital letters, and periods after every dictation.

**Scope**

- A pure, deterministic `ContextFormatter` that runs after the writing mode.
- Spacing: add a separating space before or after the insertion when the
  neighbouring character needs one; never double spaces.
- Capitalization (Clean): lower-case a capitalized common first word when the
  insertion continues a sentence; keep "I", acronyms, names, and protected tokens.
- Punctuation (Clean): drop a final period when inserting mid-sentence; avoid
  duplicating punctuation that is already next to the cursor.
- Every change names its rule, like Clean Writing transformations.

**Acceptance criteria**

- Given "Thanks for|" and dictation "the update", then the result is " the update".
- Given "We met on Monday and|" and Clean dictation "Then we left.", then the
  result is " then we left." and "Paris" or "I" at the start is never lower-cased.
- Given "Say |world" and Clean dictation "hello", then the result is "hello " (no
  period, a trailing space before "world").
- Given an empty field or a caret after ".", "!", "?", or a new line, then the
  dictation keeps its sentence capitalization.
- Exact Dictation only adjusts spacing; it never changes letters or punctuation.
- Without context the output is identical to Epic 2 behaviour.
- The formatter uses no language model, and unit tests name the rule for every change.

**Dependencies:** E3-S2, E2-S6  
**Estimate:** 8 points

---

## E3-S4 — Define the on-device language-model contract and Foundation Models engine

**User story**

As a developer, I want text rewriting behind one local contract so that voice
editing can use Apple's on-device model today and other local models later.

**Scope**

- `TextRewriting` contract: availability, request (instruction, text, language),
  typed errors, and cancellation.
- A runner that never calls an unavailable rewriter and never lets a cancelled
  request succeed; reusable contract tests and a deterministic fake.
- `FoundationModelsRewriter` in a new `Editing` module using `SystemLanguageModel`
  on device, a fresh session per request, and greedy sampling.
- Prompt instructions that return only the edited text, and output cleanup that
  strips wrapping quotes and code fences the input did not have.

**Acceptance criteria**

- Availability distinguishes ready, Apple Intelligence off, device not eligible,
  model not ready, unsupported language, and unavailable.
- An unavailable rewriter is never called; cancellation never produces a result.
- Guardrail refusals, context-window overflow, and empty output map to typed errors.
- No session, prompt, or response is retained after the request returns.
- The engine makes no application-initiated network request (verified manually).
- Contract tests pass for the fake and the error mapping of the real engine.

**Dependencies:** E3-S1  
**Estimate:** 8 points

---

## E3-S5 — Edit selected text by voice

**User story**

As a user, I want to select text, press a shortcut, and say "make this shorter"
or "translate to Spanish" so that I can revise writing without retyping it.

**Scope**

- A separate, configurable voice-editing shortcut (default ⌥⇧Space) with the
  same push-to-talk/toggle behaviour and Escape cancel.
- Capture the selected text at activation; check selection and model
  availability before recording.
- Recognise the spoken instruction, rewrite the selection on device, and replace
  the same selection through the existing delivery path.
- Recovery: copy the edited text, retry, or discard; the original text is never
  changed when anything fails.

**Acceptance criteria**

- Given a selection and a ready model, when the user speaks an instruction, then
  the selection is replaced once by the rewritten text.
- Given no selection, an excluded app, a password field, or an unavailable model,
  then recording does not start and the user sees why.
- Given the selection changed during processing, then nothing is replaced and the
  edited text can be copied.
- Given a refusal or model error, then the original text is unchanged and Retry
  and Discard are offered.
- Supported instructions (rewrite, shorten, fix grammar, make a list, translate)
  are documented, and the overlay shows "Editing selection".
- Diagnostics contain purpose, durations, and outcome identifiers, never the
  instruction, selection, or result.

**Dependencies:** E3-S2, E3-S4, E2-S7  
**Estimate:** 8 points

---

## E3-S6 — Show and control context use

**User story**

As a user, I want to see when LemmeType used text near my cursor and switch it
off everywhere or for specific apps so that I stay in control.

**Scope**

- A Settings › Context pane: formatting-context switch with a plain-language
  explanation, voice-editing switch and model status, built-in sensitive apps,
  and a user exclusion list (add from running apps, remove).
- Overlay and VoiceOver indication of context use for the current session.
- Menu-bar summary of context status.

**Acceptance criteria**

- The pane explains exactly what is read, when, and that it never leaves the Mac.
- Turning the formatting switch off stops context capture from the next activation.
- Adding an app to the exclusion list stops all context use for that app from the
  next activation; removing it restores it.
- During a session the overlay shows "Using text near the cursor" when context
  was captured, or why it was not, and VoiceOver announces it.
- Voice-editing status shows whether the on-device model is ready and how to enable it.

**Dependencies:** E3-S1, E3-S3, E3-S5  
**Estimate:** 5 points

---

## E3-S7 — Validate context-aware writing and voice editing end-to-end

**User story**

As a product team, we want evidence that context use is private, correct, and
compatible so that Epic 3 is judged by real behaviour in real apps.

**Scope**

- End-to-end tests from shortcut through capture, recognition, formatting or
  rewriting, and delivery with fakes only at the OS edges.
- Canary tests proving context, selected text, instructions, and results never
  reach diagnostics.
- Manual acceptance steps for context reading, exclusions, password fields, voice
  editing, and network silence during rewriting.
- Context and voice-edit columns in the insertion matrix.
- A proposed latency threshold for voice editing.

**Acceptance criteria**

- End-to-end tests cover mid-sentence dictation, sentence-start dictation,
  excluded apps, password fields, voice editing success, refusal, and changed selection.
- Canary strings in context, selection, instruction, and rewrite never appear in
  the diagnostics report.
- The manual checklist covers every criterion CI cannot verify.
- The insertion matrix lists context readability and voice-edit results per app.
- A voice-edit latency threshold is documented as Proposed.

**Dependencies:** E3-S1 through E3-S6  
**Estimate:** 5 points

## Epic 3 story order

1. E3-S1
2. E3-S2 and E3-S4
3. E3-S3 and E3-S5
4. E3-S6
5. E3-S7
