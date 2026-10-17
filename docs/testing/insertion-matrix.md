# Supported-app insertion matrix (E2-S7, E2-S8, E2-S10, E3-S7)

Run MA-28 (insertion) and MA-29 (clipboard fallback) in each app with a
team-signed build and record the result. "Path" is what LemmeType used:
**AX** = Accessibility insertion, **Paste** = clipboard fallback with
restoration, **Copy** = text left on the clipboard / Copy Text.

Expected behaviour comes from how each app exposes its text fields to
Accessibility; the *Result* columns are filled in by the manual run.

| App (version) | Field | Expected path | Caret insert | Selection replaced | Target change blocked | Clipboard restored | Result / date / Mac |
|---|---|---|---|---|---|---|---|
| Mail | Message body | AX | | | | n/a | Not yet run |
| Messages | Message field | AX | | | | n/a | Not yet run |
| Notes | Note body | AX | | | | n/a | Not yet run |
| Safari | `<textarea>` | AX | | | | n/a | Not yet run |
| Google Chrome | `<textarea>` | AX, or Paste when the page ignores AX writes | | | | | Not yet run |
| Microsoft Word | Document body | Paste (Word ignores AX selected-text writes in some builds) | | | | | Not yet run |
| Slack (Electron) | Message composer | Paste (Electron ignores AX writes) | | | | | Not yet run |
| Visual Studio Code | Editor | Paste | | | | | Not yet run |
| Any app | Password field | Nothing typed; Copy offered | n/a | n/a | n/a | n/a | Not yet run |

## Context and voice editing (E3-S7)

Run MA-32 (context) and MA-34 (voice editing) in each app. *Context readable*
means `AXStringForRange` returned text so formatting used it; apps that don't
expose ranges behave exactly as in Epic 2. *Voice edit* is the path the edited
text took; *Undo* is whether ⌘Z in the app restores the original.

| App (version) | Context readable (expected) | Formatting joined the sentence | Voice edit (expected path) | Same selection replaced | Undo restores | Result / date / Mac |
|---|---|---|---|---|---|---|
| Mail | Yes | | AX | | | Not yet run |
| Messages | Yes | | AX | | | Not yet run |
| Notes | Yes | | AX | | | Not yet run |
| TextEdit | Yes | | AX | | | Not yet run |
| Safari | `<textarea>`: yes | | AX | | | Not yet run |
| Google Chrome | Page-dependent | | AX, or Paste | | | Not yet run |
| Microsoft Word | Build-dependent | | Paste | | | Not yet run |
| Slack (Electron) | No (Epic 2 behaviour) | n/a | Not available — "Select the text…" | n/a | n/a | Not yet run |
| Visual Studio Code | No (Epic 2 behaviour) | n/a | Not available | n/a | n/a | Not yet run |
| 1Password / Keychain Access | Never read (built-in) | n/a | Refused before recording | n/a | n/a | Not yet run |
| Any app | Password field: never read | n/a | Refused before recording | n/a | n/a | Not yet run |

## Failure evidence

Every unsupported behaviour must end in a safe state with no data loss:

| Situation | What LemmeType does | Covered by |
|---|---|---|
| App ignores AX writes (count unchanged) | Verified nothing was inserted → clipboard fallback (or Copy Text) | `AccessibilityInsertionTests.appsThatIgnoreWritesAreDetectedWithoutDuplicates`, `ClipboardFallbackTests` |
| AX write errors and cannot be verified | No automatic retry or paste (avoids duplicates); Copy Text offered | `unverifiableErrorsAreUncertainSoNothingIsRetried` |
| Focus moved to another field or app | Nothing typed; Copy Text / Retry Insert | `aDifferentFocusedFieldNeverReceivesText` |
| Password field or secure keyboard entry | Nothing typed or read; Copy Text | `passwordFieldsAreNeverWrittenOrRead`, `secureKeyboardEntryBlocksInsertion` |
| Paste not consumed in time | Clipboard restored; transcript kept for Copy Text | `ClipboardFallbackTests.timedOutPasteRestoresAndKeepsTheTranscript` |
| User copies something during the paste | Newer clipboard kept, not overwritten | `ClipboardFallbackTests.userClipboardChangeIsNeverOverwritten` |
| Clipboard holds data that can't be copied back | No automatic paste; Copy Text | `ClipboardFallbackTests.unrestorableClipboardIsNeverTouched` |
| Voice edit: selection changed during processing | Nothing replaced; edited text kept for Copy Text | `AccessibilityInsertionTests.changedSelectionIsNotReplaced`, `ContextEndToEndTests.changedSelectionIsNotReplaced` |
| Voice edit: model refused or failed | Selection unchanged; Retry (when useful) or Discard | `ContextEndToEndTests.refusalLeavesTheTextUnchanged` |
| Voice edit: no selection / app not readable | Refused before recording | `ContextEndToEndTests.noSelectionNeverRecords` |
| Context: excluded app, sensitive app, password field | Nothing read; dictation still works | `ContextEndToEndTests.excludedAppIsNeverRead`, `…passwordFieldIsNeitherReadNorTyped` |
