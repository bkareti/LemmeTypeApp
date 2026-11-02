# LemmeType privacy threat model

Maintained with the code. `scripts/check-privacy-docs.py` (`make privacy-docs-check`)
fails when a row has no control or no verification that exists, so this page
cannot drift away from the tests. Decisions behind it: [ADR 0025](../decisions/0025-privacy-data-and-history.md).
Release use: [privacy release checklist](privacy-release-checklist.md).

## What we protect

| Asset | Where it lives | Sensitivity |
|---|---|---|
| Voice recording | A temporary file during a session | High |
| Dictated text | Memory; the target app; optionally the history | High |
| Text near the cursor and the selection | Memory during a session | High |
| Clipboard | System pasteboard during a paste fallback | High |
| History file | Application Support, owner-only, opt-in | High |
| Vocabulary, snippets, modes | Application Support, owner-only | Medium |
| Diagnostics | Memory; a report only if the user saves one | Medium |
| Downloaded models | Application Support | Low (large, not private) |
| Build and release pipeline | Maintainer's Mac and CI | High (supply chain) |

## Who might attack

- **Network observer or remote service** — wants audio or text in transit.
- **Another app on this Mac** — runs as the same user; can read user files and the pasteboard.
- **Someone with the unlocked Mac, or a backup** — reads files the app keeps.
- **A person who receives a diagnostics report** — support, a public issue.
- **A bad dependency, model, or build** — supply chain.
- **Text in a document or dictation** — tries to act as an instruction to the rewriting model.
- **The user's own mistake** — wrong app, wrong field, a password in view.

## Trust boundaries

1. LemmeType ↔ other apps (Accessibility reads and writes, the pasteboard).
2. LemmeType ↔ macOS services (Speech Recognition on device, Foundation Models on device).
3. LemmeType ↔ the network (only the model host, after the user confirms).
4. LemmeType ↔ the disk, as the user's account.

## Threats

Verification cells list `tests`, `scripts/…` files, `make` targets, and `MA-n`
manual steps in backticks; the checker resolves every one.

| ID | Threat | Control | Verification | Residual risk |
|---|---|---|---|---|
| T-01 | Audio, text, or context is sent over the network | No network code outside `docs/security/network-allowlist.txt`; ephemeral session; a socket probe during full sessions | `scripts/check-network-usage.sh`, `make network-check`, `NetworkSilenceTests`, `MA-54` | A short-lived socket between probe samples could be missed; the real-Mac monitor covers it |
| T-02 | A recording stays on disk | Owner-only temp file deleted on delivery, cancel, failure, discard, quit, and next launch | `AudioCaptureServiceTests`, `RecordingSessionTests`, `make privacy-check`, `MA-56` | A power cut leaves a file until the next launch |
| T-03 | Dictated text is stored without consent | History is off by default; with it off the store is never read or written | `DictationHistoryServiceTests`, `PrivacyEndToEndTests`, `MA-55` | None known |
| T-04 | Another user or process reads the history | Owner-only file (0600) in a 0700 folder; opt-in; atomic writes | `FileDictationHistoryStoreTests`, `MA-58` | Same-user malware, an unlocked Mac, or a backup can read it; FileVault is recommended; no app-level encryption yet |
| T-05 | A password field or password manager is read or recorded | Built-in sensitive-app list and password-field checks; history skips excluded and sensitive apps and voice edits | `ContextPolicyTests`, `CursorContextReaderTests`, `DictationHistoryServiceTests`, `MA-33` | An app that hides a secret in an ordinary text field cannot be told apart |
| T-06 | Cursor context or the selection is kept or logged | Read once at activation, held in memory, forgotten with the session | `ContextEndToEndTests`, `DiagnosticsCanaryTests`, `MA-32` | None known |
| T-07 | A diagnostics report reveals content | Redaction by construction; fixed report schema; user previews and saves | `DiagnosticsPrivacyTests`, `DiagnosticsReportSchemaTests`, `DiagnosticsCanaryTests`, `MA-18` | A new field added without review; the schema test fails until reviewed |
| T-08 | The paste fallback loses or leaks the user's clipboard | Change-count guarded restore; used only when insertion failed | `ClipboardFallbackTests`, `MA-29` | The clipboard briefly holds dictated text; a crash in that window leaves it |
| T-09 | A downloaded model is tampered with | Pinned URL, size, and SHA-256; allowlisted host; verified before each launch's first use | `ModelAssetStoreTests`, `ModelCatalogTests`, `MA-44` | A compromised upstream plus a matching catalog change in a reviewed PR |
| T-10 | An analytics SDK, entitlement, or permission slips in | Allowlists with justifications; analytics names banned; Hardened Runtime required | `scripts/check-security-config.py`, `make security-check` | A reviewer approving a bad allowlist edit |
| T-11 | Dictated text acts as an instruction to the model | Fixed instruction text; dictation passed as data; meaning check rejects changed facts | `StyleRewritingPipelineTests`, `PreservationCheckerTests`, `MA-51` | The on-device model may still produce odd wording; the user reviews before insert |
| T-12 | Text goes to the wrong app or field | Insertion only if the captured target is unchanged; otherwise Copy is offered | `AccessibilityInsertionTests`, `MA-28` | The user focuses the wrong field before pressing the shortcut |
| T-13 | Delete All Local Data misses something | One model removes history, personalization, leftover audio, and diagnostics; reports what it removed | `PrivacyOverviewModelTests`, `PrivacyEndToEndTests`, `MA-56` | Copies in backups and exported files stay; the Privacy pane says so |
| T-14 | The privacy text misleads the user | Plain-language checks (short sentences, no jargon) and a person reads it | `PrivacyTextTests`, `MA-57` | A reading check is a floor, not proof of understanding |
| T-15 | An unreadable or newer data file is overwritten | The file is moved aside and reported, never overwritten | `FileDictationHistoryStoreTests`, `FilePersonalizationStoreTests`, `MA-58` | None known |
| T-16 | The update check is spoofed, misleads the user, or runs attacker code | The app reads release metadata only and never downloads or runs code; one anonymous request, user-started or opt-in weekly, never during a session; redirects and links limited to the project's GitHub pages; size capped; no downgrade offer | `GitHubReleaseFeedTests`, `UpdateCheckerTests`, `UpdatesSettingsModelTests`, `MA-60` | GitHub, or someone who controls the user's network and TLS trust, can show a false "new version" message; it only opens a GitHub page in the browser, where the download is notarized and checksummed |
| T-17 | A crash or force-quit leaves a recording or hides that something went wrong | Leftover audio is deleted at the next launch; a marker shows a one-time notice and a diagnostic; nothing about the crash is sent | `LaunchSentinelTests`, `CrashRecoveryEndToEndTests`, `MA-62` | A power cut during a paste fallback can leave dictated text on the clipboard |
| T-18 | A release artifact carries a debug entitlement, an unsigned part, or bundled test data | The release scripts check Hardened Runtime, entitlements, signature, and contents; notarization is required for a shipped build | `scripts/verify-release.sh`, `scripts/tests/test-verify-release.sh`, `MA-59` | Notarization and the first real signed build need the maintainer's credentials and are checked by hand |

## Accepted risks

- **Any app the user has granted Accessibility can read what LemmeType inserts.**
  That is how macOS Accessibility works; the Permissions pane says what the permission allows.
- **The pasteboard is shared.** Copy and the paste fallback put dictated text on
  the clipboard on purpose; other apps and clipboard managers can read it.
- **History is not encrypted by LemmeType.** It relies on file permissions and
  FileVault. Revisit if users ask for a lock.
- **Backups.** Time Machine copies Application Support unless excluded.

## Open items

1. App-level encryption or a lock for the history (owner: product).
2. The update check (Epic 7) is the second network file; its threat is T-16.
