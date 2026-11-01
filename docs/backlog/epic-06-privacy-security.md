# Epic 6 — privacy, security, and data controls

## Epic issue body

### Objective

Turn the local-first promise into behavior that the team, CI, and the user can
check, instead of a claim in the product brief.

### Business value

LemmeType listens to a person's voice and writes into their private messages and
documents. Trust is the product. Every promise ("nothing leaves this Mac",
"nothing is kept unless you ask") needs a test, a visible control, and a plain
explanation, so that a privacy review, a skeptical user, or a future change
cannot quietly break it.

### In scope

- One decision record for what data LemmeType handles, where each kind lives,
  how long it lives, and how it is removed (ADR 0025).
- Automated proof that dictation, cleanup, translation, and rewriting do not
  open a network connection, and a list of the only code allowed to.
- An opt-in dictation history with a retention period, export, and deletion.
  Off by default. Text only; never audio, cursor context, or app identity.
- A Privacy pane that explains in plain language what each permission is for,
  what context is read and when, and what is stored, with Delete All Local Data.
- A check that nothing sensitive reaches diagnostics, logs, errors, or any
  analytics, and a rule that there is no analytics.
- CI guardrails for entitlements, usage strings, dependencies, and network APIs.
- A maintained privacy threat model and release checklist that CI keeps honest.

### Out of scope

- Audio retention. No setting keeps audio; "Save Audio…" after a failure stays
  an explicit one-time export (ADR 0013).
- History search, tags, sync, backup, or sharing between devices.
- App-level encryption or a lock for history (the file is owner-only; FileVault
  is recommended in the Privacy pane). Revisit if the threat model asks for it.
- Analytics, telemetry, or crash upload of any kind.
- Turning on the App Sandbox (ADR 0001; the distribution decision is Epic 7).
- iPhone and iPad (Epic 8).

### Epic acceptance criteria

- All child stories are accepted.
- CI fails if any module other than the approved ones can reach the network, and
  a runtime check shows zero internet sockets during full fake-OS dictation,
  cleanup, translation, and rewriting.
- With defaults, no audio, text, or context is written to disk after a session.
- History is off by default; when on, it has a retention period, export, delete
  one, and delete all, and never records audio, context, or app identity.
- Canary text never appears in logs, diagnostics, errors, or exports.
- Every permission and every kind of stored data is explained in plain language
  inside the app.
- Entitlements, usage strings, and dependencies cannot change without a
  reviewed allowlist edit.
- The threat model and privacy release checklist exist, are linked to real
  tests, and CI fails when a link goes stale.

---

## E6-S1 — Decide the data inventory, retention, and history model

**User story**

As a product team, we want one recorded decision on what data LemmeType handles
and keeps, so that the other stories do not invent privacy rules on their own.

**Scope**

- ADR 0025 with a data inventory: audio, transcript, final text, cursor
  context, selected text, clipboard, vocabulary/replacements/snippets, history,
  diagnostics, models, preferences. For each: where it lives, how long, who can
  read it, how it is removed.
- History model: what an entry holds (final text the user accepted by Insert or
  Copy, time, mode, language, delivery method, word count) and what it never
  holds (audio, text from before a rewrite, cursor context, selection, app name
  or bundle id).
- Retention choices (Off by default, 1 day, 1 week, 1 month, until deleted) and
  a hard cap on entries; what turning History off or shortening it does.
- The decision on audio and context retention: no option exists, so both are
  always off.
- The network policy (allowlist of files that may use network APIs) and the
  rule that updates (Epic 7) are user-initiated.
- An update to the privacy rules in the coding standards that allows history as
  the one other place dictated text may be stored, only when the user opts in.

**Acceptance criteria**

- The ADR has the full inventory table with no empty cell.
- The ADR names the exact retention choices, the entry cap, the file location,
  and the file protections.
- The ADR states which sessions are never recorded (password or secure input,
  excluded and sensitive apps, failed or discarded sessions, voice-editing
  selections).
- The coding standards and `CLAUDE.md` mention history and point to the ADR.
- Open questions are listed with a proposed default.

**Dependencies:** ADR 0008, ADR 0011, ADR 0013, ADR 0017, ADR 0020  
**Estimate:** 3 points

---

## E6-S2 — Prove Local mode is network-silent in CI

**User story**

As a user, I want proof that dictation and text processing never use the
network, so that I can trust the "nothing leaves this Mac" promise.

**Scope**

- A static check (`scripts/check-network-usage.sh`) that fails when any source
  file outside `docs/security/network-allowlist.txt` uses a network API
  (`URLSession`, `URLRequest`, `NWConnection`, `NWListener`, `import Network`,
  `CFNetwork`, `NSURLConnection`, raw sockets, or launching `curl`/`nc`).
- A runtime probe in `TestSupport` that lists the internet sockets open in the
  current process, and a hosted test that runs full fake-OS sessions (Exact,
  Clean, personalization, context formatting, translation review, tone
  rewrite, voice editing) and asserts that none opened.
- A test that the model downloader is never started by dictation, cleanup,
  translation, or rewriting.
- `make network-check`, added to `make ci` and the CI job.
- A manual step for a real Mac with a network monitor (extends MA-19 and MA-31).

**Acceptance criteria**

- The allowlist holds only the model downloader; adding a network call anywhere
  else fails the check (fixture test of the script).
- The probe sees a deliberately opened local socket (so a silent probe cannot
  pass by being broken), and sees none during the full sessions.
- A fake downloader records zero calls across all session types.
- The check runs in `make ci` and in the CI workflow.
- The manual step lists the tool, the actions to perform, and the expected result.

**Dependencies:** E6-S1, E2-S10  
**Estimate:** 5 points

---

## E6-S3 — Keep an opt-in dictation history on this Mac

**User story**

As a user who wants to find something I dictated earlier, I want LemmeType to
keep a history only if I turn it on, so that nothing is stored without my choice.

**Scope**

- Domain: `HistoryRetention` (off, one day, one week, one month, until
  deleted), `DictationHistoryEntry`, the pure `DictationHistory` (newest
  first, age purge, entry cap), and the `DictationHistoryRecording` and
  `DictationHistoryStoring` protocols.
- `AppPreferences.historyRetention`, default off.
- `FileDictationHistoryStore` (Support): versioned JSON in Application Support,
  owner-only (0600 file, 0700 directory), atomic writes, an unreadable file is
  moved aside and reported, never overwritten.
- Recording after a successful delivery or copy of the final text, once per
  result. Not recorded: failed or discarded sessions, password or secure input,
  excluded or sensitive apps, voice-editing selections.
- Purge of expired entries at launch and whenever an entry is recorded.
- Diagnostics record counts and identifiers only.

**Acceptance criteria**

- With retention off, nothing is written (no file, no directory), including
  after a full session with canary text.
- With retention on, one entry per delivered or copied result holds the
  expected fields and no others (encoded keys are asserted).
- Age purge, entry cap, and ordering are tested with an injected clock.
- The file and directory permissions are 0600 and 0700.
- A corrupt or newer-version file is moved aside, reported, and does not crash.
- Sessions that were blocked by context policy, or that failed or were
  discarded, record nothing.
- A stored sample from the first version stays readable (migration test).

**Dependencies:** E6-S1, E4-S1, E3-S1  
**Estimate:** 8 points

---

## E6-S4 — Control history in Settings: retention, export, and deletion

**User story**

As a user, I want to choose how long history is kept, see it, export it, and
delete it, so that I stay in control of what is stored.

**Scope**

- Settings › Privacy › History: an off-by-default switch, a retention picker
  with a plain explanation, and the recent entries (date, short preview).
- Per entry: Copy and Delete. For the whole history: Export… (JSON saved where
  the user chooses) and Delete All… with confirmation.
- Turning History off, or choosing a shorter period, says what will be deleted
  and asks first; Cancel leaves the setting unchanged.
- Accessibility labels and identifiers; deletion and export results announced.
- The pane shows an honest empty state, and a clear message if the file could
  not be read.

**Acceptance criteria**

- History is off on a fresh install and the pane says so.
- Choosing a shorter period deletes expired entries only after confirmation.
- Turning History off deletes the entries after confirmation; Cancel keeps both.
- Delete one and Delete All remove the entries from the screen and the file
  (tests read the file back).
- Export writes valid JSON with a version number, only where the user picks.
- Every control has a label and identifier; a UI test covers the pane with a
  fake store.

**Dependencies:** E6-S3  
**Estimate:** 8 points

---

## E6-S5 — Explain data use in plain language, and delete everything

**User story**

As a user, I want a page that tells me in plain words what LemmeType uses my
permissions for, what it reads, and what it stores, and a way to wipe it all,
so that I can decide with full information.

**Scope**

- Settings › Privacy › Overview: for each kind of data in the ADR 0025
  inventory, what it is, where it lives, how long, and how to remove it.
- A `PermissionExplanation` per permission (Microphone, Accessibility, Speech
  Recognition): why it is needed, what is read, what is never done, how to
  turn it off. Used by onboarding, Settings › Permissions, and the Overview.
- A plain description of context collection (when, how much, which apps are
  skipped) linking to Settings › Context.
- Delete All Local Data…: history, personalization, any leftover session audio,
  and the in-memory diagnostics, with an optional "also remove downloaded
  models" choice that is off by default. Shows what was removed.
- The text is localizable and avoids jargon.

**Acceptance criteria**

- Every `PermissionKind` and Speech Recognition has all four explanation parts
  (unit test over the table).
- A reading check: sentences are at most 25 words and no entry uses a banned
  term list (for example "TCC", "AX", "entitlement"). The test fails otherwise.
- Delete All Local Data removes the history file, the personalization file,
  and session audio, and leaves models unless the user chose otherwise
  (tests read the disk).
- Running it twice is safe and reports nothing left to delete.
- A UI test opens the Overview and the confirmation, and checks identifiers.

**Dependencies:** E6-S1, E6-S4, E4-S8  
**Estimate:** 5 points

---

## E6-S6 — Keep sensitive data out of diagnostics, logs, and analytics

**User story**

As a user, I want to know that what I say and write never ends up in logs or
reports, so that sharing a diagnostics report is safe.

**Scope**

- A canary suite that runs every session type (Exact, Clean, personalization,
  context formatting, translation review, rewrite review, voice editing,
  history on) and the failure paths, with unique canary text in audio
  metadata, transcripts, cursor context, selections, clipboard, vocabulary,
  history, app names, and file paths. It asserts that none appears in the
  diagnostics buffer, the encoded report, error identifiers and messages, or
  exported history metadata.
- A `history` diagnostics category, with counts and identifiers only.
- A schema test that fixes the top-level and event keys of
  `DiagnosticsReport`, so adding a field fails until it is reviewed.
- A written rule and a test that no analytics, telemetry, or crash-reporting
  package is linked (checked together with E6-S7).

**Acceptance criteria**

- The canary suite covers every scenario above and fails if a scenario is removed.
- No canary appears in any captured output.
- The report schema test lists the allowed keys; adding one fails the test.
- The diagnostics category list and event names are covered by an
  identifier-pattern test.
- The ADR and the Privacy pane state that LemmeType has no analytics.

**Dependencies:** E6-S3, E1-S7, ADR 0008  
**Estimate:** 5 points

---

## E6-S7 — Enforce security guardrails in CI

**User story**

As a maintainer, I want CI to stop an unreviewed change to entitlements,
permission strings, dependencies, or hardening, so that the app cannot quietly
gain a new capability.

**Scope**

- `scripts/check-security-config.py` with allowlists under `docs/security/`:
  entitlements (only audio input), `NS*UsageDescription` keys (Microphone and
  Speech Recognition), dependencies (only the pinned whisper.cpp binary), and
  required build settings (hardened runtime on for Release; no
  `get-task-allow` or library-validation bypass entitlement).
- Each allowlist entry carries a one-line justification.
- `make security-check`, added to `make ci` and the CI workflow.
- Fixture tests proving that each rule fails on a seeded violation.

**Acceptance criteria**

- The check passes on the repository today.
- Adding an entitlement, a usage string, a package, a binary target, or turning
  hardened runtime off for Release makes it fail (fixture tests).
- A banned-name list (common analytics and crash SDKs) fails the check.
- The check runs in `make ci` and in the CI workflow.
- Changing an allowlist needs a justification line, or the check fails.

**Dependencies:** E6-S1  
**Estimate:** 5 points

---

## E6-S8 — Maintain the threat model and privacy release checklist, and validate Epic 6

**User story**

As a product team, we want a threat model and a release checklist that stay true,
and end-to-end evidence for Epic 6, so that we can approve the epic and each
release.

**Scope**

- `docs/security/threat-model.md`: assets, actors, trust boundaries, a data-flow
  summary, and a threat table (id, threat, control, verification, residual
  risk) covering audio, text, context, clipboard, history, models, updates,
  diagnostics, and local attackers.
- `docs/security/privacy-release-checklist.md`, used by the release process.
- `scripts/check-privacy-docs.py`: every threat row names a control and at
  least one verification that exists (a test name, script, or MA step), and
  every release checklist item links to a script, test, or MA step.
- `PrivacyEndToEndTests`: default run leaves nothing on disk; history on records
  exactly the accepted text; Delete All Local Data leaves nothing.
- Manual steps in `docs/testing/manual-acceptance.md` for the real Mac checks.
- The release-management skill points to the checklist.

**Acceptance criteria**

- The threat model has no row without a control and a verification.
- The checker fails when a referenced test, script, or MA step does not exist
  (fixture test).
- The end-to-end tests use canary text and read the disk.
- The manual steps cover network monitoring, history, and Delete All.
- Epic 6 acceptance lists residual risks with an owner.

**Dependencies:** E6-S2 through E6-S7  
**Estimate:** 5 points

## Epic 6 story order

1. E6-S1
2. E6-S2
3. E6-S3
4. E6-S4
5. E6-S5
6. E6-S6
7. E6-S7
8. E6-S8
