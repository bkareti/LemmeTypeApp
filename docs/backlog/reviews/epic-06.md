# Readiness review — Epic 6 (privacy, security, and data controls)

Reviewed 2026-11-01 with the `story-review` skill against
`docs/backlog/epic-06-privacy-security.md`, the Epic 6 section of
`docs/roadmap.md`, issue #6, and the code on `main` (diagnostics, personalization
store, session audio lifecycle, delivery, `scripts/check-network-silence.sh`,
the `no_network_apis` SwiftLint rule), and ADRs 0001, 0008, 0011, 0013, 0017, 0020.

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E6-S1 Data inventory and history ADR | Ready | Decisions are proposed below; needs product-owner approval of the retention choices. |
| E6-S2 Network-silent proof in CI | Ready with notes | A socket probe in the test process shows our process only; a real Mac with a network monitor stays a manual step. |
| E6-S3 Opt-in history store | Ready with notes | First code that stores dictated text. Allowed only by the ADR in S1, and only after opt-in. |
| E6-S4 History controls | Ready | Reuses the pattern of the personalization data controls. Needs a new Privacy tab; width must stay fixed. |
| E6-S5 Plain-language explanations and Delete All | Ready with notes | "Plain language" is checked by a proxy (sentence length, banned words); real comprehension needs a user read-through. |
| E6-S6 Diagnostics and analytics exclusion | Ready | Extends the canary tests of ADR 0008 to later epics and history. |
| E6-S7 Security guardrails | Ready | Pure scripting plus fixtures; no OS permission needed. |
| E6-S8 Threat model, checklist, validation | Ready | Docs are checked by a script so they cannot drift. |

No blockers. The epic spans every other epic, so it is developed on top of the
latest `main` and is merged before Epic 7, which depends on its allowlists and
its Privacy pane.

## Checklist (epic level)

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Each promise gets a test and a visible control. |
| 2 | Size | Pass | Eight stories, none above 8 points. |
| 3 | Dependencies | Pass | Builds on Epics 1 to 5, 9, and 10, all merged. E6-S3 hooks the delivery step. |
| 4 | Acceptance criteria | Concern | "Plain language" has only a proxy test; thresholds on history size are proposed. |
| 5 | CI testability | Pass | Sockets, files, and scripts are testable on CI. Network monitoring on a real Mac is manual. |
| 6 | Privacy | Concern | History stores dictated text. It is off by default, text-only, owner-only on disk, and never holds audio, context, or app identity. |
| 7 | Permissions | Pass | No new permission. |
| 8 | Feasibility | Pass | libproc lists a process's sockets without special rights. |
| 9 | Out of scope | Pass | No audio retention, analytics, sync, or app lock. |
| 10 | Open decisions | Concern | See below. |

## Decisions to record (proposed defaults)

1. **History** — opt-in, off by default; text the user accepted by Insert or
   Copy; stored locally only.
2. **Entry fields** — id, time, text, mode identifier, language, delivery
   method, word count. Never audio, text before a rewrite, cursor context,
   selection, or app name.
3. **Retention** — Off (default), 1 day, 1 week, 1 month, until deleted; cap of
   1,000 entries (oldest dropped first).
4. **Turning History off** — deletes entries after confirmation; Cancel keeps the
   setting and the entries.
5. **Audio and context** — no option to keep either; both are always off.
6. **Not recorded** — password or secure-input targets, excluded and sensitive
   apps, failed or discarded sessions, voice-editing selections.
7. **File** — `Application Support/LemmeType/History/history.json`, version 1,
   0600 in a 0700 directory, atomic writes, unreadable files moved aside.
8. **Network allowlist** — only the model downloader today; the update check
   (Epic 7) is added by a reviewed edit.
9. **Encryption** — no app-level encryption in this epic; recommend FileVault and
   record the residual risk in the threat model.
10. **Analytics** — none, now or later, without a new ADR and product-owner approval.

## Open risks

- **Local attacker reading history** — mitigated by owner-only files and opt-in;
  residual risk with an unlocked Mac or a backup. Recorded in the threat model.
- **Backups** — Time Machine copies Application Support. The Privacy pane says so.
- **Plain language** — the reading check is a floor, not proof. A person outside
  the team should read the pane before acceptance (manual step).

## AC → verification map

| Acceptance area | Verification |
|---|---|
| Inventory and decisions | ADR 0025 review; `scripts/check-privacy-docs.py` |
| Network allowlist | `scripts/tests/test-network-usage.sh`, `make network-check` |
| No sockets during sessions | `NetworkSilenceTests` (hosted), `OpenSocketProbeTests` |
| History off writes nothing | `DictationHistoryStoreTests`, `PrivacyEndToEndTests` |
| History fields, purge, cap, permissions | `DictationHistoryTests`, `DictationHistoryStoreTests` |
| History controls | `HistorySettingsModelTests`, `PrivacyUITests` |
| Explanations and Delete All | `PermissionExplanationTests`, `LocalDataEraserTests` |
| Diagnostics canaries and schema | `DiagnosticsPrivacyTests`, `DiagnosticsReportSchemaTests` |
| Entitlements, usage strings, dependencies | `scripts/tests/test-security-config.py`, `make security-check` |
| Threat model drift | `scripts/tests/test-privacy-docs.py`, `make privacy-docs-check` |
| Real Mac network monitor, history, Delete All | `docs/testing/manual-acceptance.md` (MA-47 to MA-52) |
