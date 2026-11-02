# 0025 — Privacy: data inventory, retention, and the opt-in history

- Status: Accepted (retention choices await product-owner approval)
- Date: 2026-11-01
- Stories: E6-S1 … E6-S8 (issues #100–#107, epic #6)

## Context

The product brief promises that audio, text, and cursor context stay on the Mac
and that nothing is kept unless the user asks. Until now that promise lived in
several ADRs (0008 diagnostics, 0011 downloads, 0013 sessions, 0017 context,
0020 personalization) and in one coding-standards rule: "never persist
transcripts". Epic 6 needs one place that says what is handled, what is kept, for
how long, and how it is removed, plus the first feature that stores dictated
text on purpose: a history the user turns on.

## Decision

### Data inventory

| Data | Where it lives | How long | Who can read it | How it is removed |
|---|---|---|---|---|
| Audio (recording) | `$TMPDIR/LemmeType/Sessions`, owner-only, one file per session | Until the session ends | This app | Deleted after delivery, cancel, failure, discard, replacement, quit, and next launch (ADR 0013). *Save Audio…* after a failure writes a copy the user chose; that copy is theirs |
| Transcript before writing | Memory | Until the session ends or the review closes | This app | Dropped with the session |
| Final text | Memory, then the target field or the clipboard | Until delivered, copied, or discarded | The target app; for Copy, anything that reads the clipboard | Not stored. The previous clipboard is restored after a paste fallback |
| Text before a rewrite or translation | Memory (review state only) | Until the review closes | This app | Dropped with the session |
| Cursor context (≤ 240 before, ≤ 40 after the caret) | Memory | Until the session ends | This app | Dropped with the session |
| Selected text (voice editing, ≤ 4,000) | Memory | Until the session ends | This app | Dropped with the session |
| Clipboard | The system pasteboard | Only during a paste fallback | Any app | Restored after the paste (change-count guarded). Never read |
| Vocabulary, replacements, snippets, modes, app rules | `Application Support/LemmeType/Personalization/library.json`, 0600 | Until deleted | The user's account | Export, Delete All (ADR 0020), Delete All Local Data |
| **History (new, opt-in)** | `Application Support/LemmeType/History/history.json`, 0600 in a 0700 directory | The chosen retention period | The user's account | Delete one, Delete All, shorter period, Delete All Local Data |
| Diagnostics events | Memory ring buffer (500 events) | Until quit | This app | Quit. Exported only when the user saves a report (ADR 0008) |
| Models | `Application Support/LemmeType/Models` | Until removed | The user's account | Remove in Settings › Dictation › Models; optional in Delete All Local Data |
| Preferences | `UserDefaults` (flags, identifiers) | Until reset | The user's account | `defaults delete`, or uninstall |
| Launch marker (Epic 7) | `Application Support/LemmeType/State` | One run | This app | Removed on a normal quit |

### History

- **Off by default.** Nothing is created on disk until the user turns it on.
- **What an entry holds:** an id, the time, the *final text the user accepted*
  (Insert, Use Original, or Copy), the mode identifier, the language, the
  delivery method (inserted or copied), and a word count.
- **What it never holds:** audio; the text from before a rewrite or
  translation; cursor context; the voice-editing selection; the app's name or
  bundle identifier; the window title; the user's vocabulary.
- **Never recorded:** a session that failed or was discarded; a target that is a
  password field or has secure input (nothing is delivered there); an app the
  user excluded from context or one of the built-in sensitive apps (password
  managers); a voice-editing session.
- **Retention choices:** Off (default), 1 day, 1 week, 1 month, Until I delete.
  Expired entries are removed at launch and whenever an entry is recorded.
  A hard cap of 1,000 entries applies to every choice; the oldest are dropped
  first.
- **Turning History off** deletes the entries after the user confirms; Cancel
  keeps the setting and the entries. Choosing a shorter period deletes what it
  expires after the user confirms.
- **Storage:** one versioned JSON file, replaced atomically; a file that cannot
  be read, or comes from a newer version, is moved aside as
  `history-unreadable-<time>.json` and reported, never overwritten (as in
  ADR 0020).
- **Export** writes the same JSON to a place the user picks. There is no upload,
  sync, or sharing.
- **Diagnostics** record counts, the retention name, and error identifiers only.

### Audio and context retention

There is no setting that keeps audio or cursor context. Both are always off, so
the "defaults to off" criterion holds by construction and cannot be changed by a
mistaken toggle. A future option would need its own ADR.

### Network policy

- Local mode (recording, recognition, cleanup, translation, rewriting, voice
  editing, history) never uses the network. Model downloads and, from Epic 7,
  the update check are the only network code, and each starts only when the user
  asks.
- The files allowed to use network APIs are listed in
  `docs/security/network-allowlist.txt`. A CI check fails on any other file, and
  a hosted test checks that no internet socket opens during sessions.
- Adding a file to the list is a reviewed change with a justification.

### Analytics

There is none and none is allowed: no analytics, telemetry, advertising, or
crash-reporting package, no event upload, and no identifier. Diagnostics are
local until the user saves a report. A change needs a new ADR and
product-owner approval.

### Security guardrails

- Entitlements: only `com.apple.security.device.audio-input`.
- Permission strings: Microphone and Speech Recognition only.
- Dependencies: only the pinned whisper.cpp binary.
- Release builds keep Hardened Runtime and never carry `get-task-allow`.
- Each list lives in `docs/security/` with a justification per entry, and
  `scripts/check-security-config.py` fails on a change without one.

## Consequences

- The coding-standards privacy rule becomes: never log, persist, or include in
  errors audio, transcripts, text from other apps, or clipboard contents —
  except the opt-in history (this ADR) and the personalization store (ADR 0020).
- History is the second place dictated text can be written to disk. The threat
  model records the residual risk: anyone who can read the user's files (an
  unlocked Mac, a backup, malware running as the user) can read it. The Privacy
  pane recommends FileVault and says Time Machine backs up Application Support.
- Encryption of the history file inside the app is not part of this epic; the
  threat model keeps it as an open item.
- Epic 7 adds exactly one network file (the update check) to the allowlist.
- Delete All Local Data removes history, personalization, leftover session
  audio, and the in-memory diagnostics; models only if the user also chooses.

## Open questions (proposed defaults)

1. Should History store the mode *name*? No: identifier only, since names can be
   user-written text.
2. Should History keep translations or rewrites? Yes, but only the text the user
   accepted, never both versions.
3. Is 1,000 entries enough? It keeps the file small (well under a megabyte for
   typical dictations). Revisit with real use.
4. Should the app lock History? Not now; revisit after the threat-model review.
