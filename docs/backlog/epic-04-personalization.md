# Epic 4 — personalization, modes, vocabulary, and snippets

## Epic issue body

### Objective

Let users shape LemmeType around their own words and writing habits: teach it
names and jargon, replace phrases they say with what they mean, insert reusable
snippets by voice, and group transcription, cleanup, style, and output choices
into modes that switch automatically per application.

### Business value

Generic dictation misspells the names, products, and terms people use most and
forces the same edits again and again. Personalization removes those repeated
fixes, and per-app modes make LemmeType behave right in a chat app, an email
client, and a code editor without the user changing settings each time.

### In scope

- A local personalization library (vocabulary, replacements, snippets, custom
  modes, per-app rules) with validation and a private on-disk store.
- Deterministic vocabulary and replacement rules applied to every dictation,
  plus vocabulary hints passed to the recognition engines.
- Whole-utterance snippet expansion.
- Modes that select engine and language, writing mode and cleanup rules,
  personalization, final-punctuation style, and output (insert or copy only).
- Manual mode choice in Settings and the status menu, and automatic mode
  choice by frontmost application.
- Settings panes to manage everything, and export, import, and delete-all.
- End-to-end, privacy, and manual validation.

### Out of scope

- Language-model tone or style rewriting of dictation (voice editing already
  covers explicit rewrites; a style model needs Epic 5 model work first).
- Cloud sync, accounts, and team-shared vocabularies (product non-goals).
- Snippet variables (dates, clipboard, cursor placement) and inline expansion
  inside longer sentences.
- Per-website or per-document rules; only per-application rules.
- History of dictations or of personalization changes (Epic 6).
- New dictation languages (later scope).

### Epic acceptance criteria

- All child stories are accepted.
- Users can manage vocabulary, replacements, and reusable snippets.
- Modes can select transcription, cleanup, style, and output behavior.
- Modes can be activated manually or by application.
- Personalization data stays on the Mac, is never logged or put in
  diagnostics, and is exportable and deletable.

---

## E4-S1 — Define the personalization library and its local store

**User story**

As a user, I want my words, replacements, and snippets kept safely on my Mac so
that LemmeType remembers them without ever sending or logging them.

**Scope**

- Domain types: `VocabularyEntry` (term and optional "sounds like" spellings),
  `Replacement` (spoken phrase → written text), `Snippet` (trigger phrase →
  expansion), and `PersonalizationLibrary` holding them with stable ids.
- Validation with a typed `PersonalizationError` for empty values, lengths,
  duplicates, and count limits.
- A `PersonalizationStoring` protocol and a file-backed store in `Support`:
  versioned JSON in Application Support, written atomically, owner-only
  permissions.
- An ADR that allows persisting personalization data locally while keeping it
  out of logs, diagnostics, and preferences.

**Acceptance criteria**

- Limits: vocabulary terms ≤ 100 characters with ≤ 5 "sounds like" spellings,
  replacement phrases ≤ 100 and written text ≤ 1,000 characters, snippet
  triggers ≤ 60 and expansions ≤ 4,000 characters; at most 500 vocabulary
  entries, 500 replacements, and 200 snippets.
- Duplicate vocabulary terms, spoken phrases, and snippet triggers are rejected
  case-insensitively, and every error has a stable lowercase identifier.
- Saving and loading returns an equal library; the file is mode 0600 in a 0700
  directory and is replaced atomically.
- An unreadable file or one from a newer version is never overwritten: loading
  reports `personalization.unreadable`, moves the file aside, and starts empty.
- Printing or interpolating any personalization type never reveals its text.
- Nothing personal is written to `UserDefaults`; diagnostics may record counts only.

**Dependencies:** E2-S6  
**Estimate:** 5 points

---

## E4-S2 — Apply vocabulary and replacements to dictation

**User story**

As a user, I want LemmeType to spell my names and terms correctly and turn
phrases I say into the text I mean so that I stop fixing the same words.

**Scope**

- A pure `Personalizer` that runs after the writing mode and before context
  formatting, so written forms are final and Clean Writing cannot alter them.
- Vocabulary: a term's "sounds like" spellings, and the term in any letter
  case, become the term as written.
- Replacements: a spoken phrase becomes its written text.
- Matching is whole-word and case-insensitive, longest phrase first, in one
  pass; replaced text is never matched again. Each change names its rule.
- Recognition hints: vocabulary terms are passed to Apple Speech
  (`contextualStrings`) and Whisper (initial prompt).

**Acceptance criteria**

- Given vocabulary "LemmeType" sounding like "lemme type", when the transcript
  is "I use lemme type daily", then the delivered text is "I use LemmeType daily".
- Given replacement "my email" → "pat@example.com", when Clean dictation is
  "send it to my email", then the result is "Send it to pat@example.com."
- "myemail" and "my emails" are not replaced (whole words only).
- The longest matching phrase wins and replaced text is not matched again.
- Rules apply in Exact and Clean; in Exact no other word changes.
- Up to 100 vocabulary terms are passed as recognition hints; none when the
  library is empty.
- Diagnostics record the number of changes only, never the words.

**Dependencies:** E4-S1, E2-S2, E2-S3  
**Estimate:** 5 points

---

## E4-S3 — Insert snippets by voice

**User story**

As a user, I want to say a short trigger like "sign off" and get my saved text
so that I can insert things I write often in one step.

**Scope**

- When the whole utterance matches a snippet trigger (ignoring letter case,
  surrounding whitespace, and trailing punctuation), deliver the expansion
  exactly instead of the transcript.
- The expansion skips the writing mode and replacements; with formatting
  context only spacing is adjusted.
- Line breaks in an expansion are delivered as written.

**Acceptance criteria**

- Given snippet "sign off" → "Best regards,\nPat", when the user says "Sign off."
  then "Best regards,\nPat" is inserted exactly.
- Given the trigger inside a longer sentence, nothing expands.
- Snippets are never applied in voice-editing sessions.
- Diagnostics record that a snippet was used, never its trigger or text.

**Dependencies:** E4-S1, E4-S2  
**Estimate:** 3 points

---

## E4-S4 — Manage vocabulary, replacements, and snippets in Settings

**User story**

As a user, I want one place to add, edit, and remove my vocabulary,
replacements, and snippets so that personalization is easy to keep current.

**Scope**

- Settings › Personalization with Vocabulary, Replacements, and Snippets lists.
- Add and edit in a sheet with inline validation; delete with a button per row.
- Counts against limits, a plain-language explanation, and the load error
  (if any) with a way to continue.
- Changes are saved immediately and used from the next dictation.

**Acceptance criteria**

- Each kind can be added, edited, and deleted; invalid input shows the
  validation message and is not saved.
- A change applies from the next dictation, never the one in progress.
- If the store could not be read, the pane says so and that the old file was kept.
- Every control has an accessibility label and the pane works with VoiceOver.

**Dependencies:** E4-S1  
**Estimate:** 5 points

---

## E4-S5 — Define dictation modes

**User story**

As a user, I want modes that bundle how LemmeType transcribes, cleans, styles,
and outputs text so that I can switch behavior with one choice.

**Scope**

- `DictationMode`: name; transcription (engine preference and language);
  cleanup (Exact or Clean and the enabled Clean rules); style (vocabulary and
  replacements on/off, snippets on/off, final period kept or omitted); output
  (insert or copy only, optional trailing space).
- Built-in Exact, Clean, and Message (Clean without a final period) modes with
  stable identifiers; up to 20 custom modes stored in the personalization library.
- The existing writing-mode preference migrates to the matching built-in mode.
- The session captures the resolved mode when recording starts; the pipeline
  applies every mode setting.

**Acceptance criteria**

- Built-in Exact and Clean produce exactly the Epic 2 output, and an existing
  writing-mode preference selects the matching built-in mode.
- A custom mode's engine, language, writing mode, cleanup rules,
  personalization and snippet switches, final-period style, and output are all
  honored by the pipeline (one test per setting).
- The mode is captured at recording start; changing it mid-session affects only
  the next session.
- Copy-only output puts the text on the clipboard without touching the target
  app, and the overlay says it was copied.
- Diagnostics record the built-in mode identifier or `custom`, never a mode name.

**Dependencies:** E4-S2, E4-S3, E2-S9  
**Estimate:** 8 points

---

## E4-S6 — Choose and manage modes

**User story**

As a user, I want to create my own modes and pick the active one from Settings
or the menu bar so that switching behavior takes a second.

**Scope**

- Settings › Modes: list of built-in and custom modes, the default mode, and
  create, duplicate, edit, and delete for custom modes.
- The status menu lists modes and checks the active one (replacing the
  Exact/Clean picker).
- The overlay shows the session's mode name; VoiceOver announces it.

**Acceptance criteria**

- Built-in modes can be duplicated but not edited or deleted.
- Mode names are 1–40 characters and unique (case-insensitive).
- Deleting a mode that is the default or used by an app rule asks first, then
  falls back to Clean and removes those rules.
- Choosing a mode in the menu or Settings applies from the next session.
- The overlay shows the mode name during recording.

**Dependencies:** E4-S5  
**Estimate:** 5 points

---

## E4-S7 — Activate modes by application

**User story**

As a user, I want LemmeType to pick a mode for the app I'm dictating into so
that chat, email, and code get the right behavior automatically.

**Scope**

- App rules map a bundle identifier to a mode; at most 100 rules, stored in
  the personalization library.
- A pure `ModeResolver` picks the mode at activation: the rule for the target
  app, otherwise the default mode.
- Settings › Modes gains a per-app section: add from running apps, choose a
  mode, remove.
- The overlay shows when a mode came from an app rule.

**Acceptance criteria**

- Given a rule Slack → Message, dictation in Slack uses Message and dictation
  elsewhere uses the default mode.
- Without a target or bundle identifier, the default mode is used.
- A rule whose mode no longer exists falls back to the default mode.
- Rules are evaluated only at activation.
- Diagnostics record whether the mode came from the default or an app rule,
  never the app.

**Dependencies:** E4-S5, E4-S6  
**Estimate:** 5 points

---

## E4-S8 — Export, import, and delete personalization data

**User story**

As a user, I want to back up, move, and erase my personalization so that my
data stays mine.

**Scope**

- Export the whole library (vocabulary, replacements, snippets, custom modes,
  app rules) as versioned, readable JSON to a file the user chooses.
- Import with validation and a summary, either merging (skipping duplicates)
  or replacing.
- Delete All, after confirmation, removes the store file and resets modes.

**Acceptance criteria**

- Exporting and importing into an empty library reproduces it exactly.
- An invalid file, or one with an unknown format version, is rejected with a
  message and changes nothing.
- Merge skips duplicates and reports how many items were added and skipped.
- Delete All removes the file and returns personalization and modes to the
  defaults; dictation keeps working.
- Files are written only where the user chooses; diagnostics record counts and
  outcome identifiers only.

**Dependencies:** E4-S1, E4-S5, E4-S7  
**Estimate:** 5 points

---

## E4-S9 — Validate personalization and modes end-to-end

**User story**

As a product team, we want evidence that personalization works across the whole
dictation flow and never leaks so that Epic 4 is judged by real behavior.

**Scope**

- End-to-end tests from shortcut through recognition, personalization, mode,
  and delivery with fakes only at the OS edges.
- Canary tests proving vocabulary, replacements, snippets, and mode names never
  reach diagnostics.
- Manual acceptance steps for Settings, per-app rules in real apps, and the
  export/import file dialogs.

**Acceptance criteria**

- End-to-end tests cover vocabulary, replacement, snippet, a custom mode,
  copy-only output, a per-app mode, and an export/import round trip.
- Canary strings in every personalization field never appear in the
  diagnostics report.
- The manual checklist covers every criterion CI cannot verify.

**Dependencies:** E4-S1 through E4-S8  
**Estimate:** 3 points

## Epic 4 story order

1. E4-S1
2. E4-S2 and E4-S4
3. E4-S3
4. E4-S5
5. E4-S6
6. E4-S7
7. E4-S8
8. E4-S9
