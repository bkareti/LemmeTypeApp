# Readiness review — Epic 7 (quality, packaging, and release readiness)

Reviewed 2026-11-01 with the `story-review` skill against
`docs/backlog/epic-07-quality-release.md`, the Epic 7 section of
`docs/roadmap.md`, issue #7, and the code on `main` (`Config/*.xcconfig`,
`project.yml`, `.github/workflows/ci.yml`, `scripts/check-release-artifact.sh`,
the release-management skill, the Localizable catalog, the Settings panes), and
ADRs 0001, 0003, 0008, 0011, 0022.

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E7-S1 Distribution and update ADR | Ready with notes | The App Sandbox experiment needs a real Mac and Accessibility approval; the ADR stays *Proposed* until it runs and the product owner approves. |
| E7-S2 Verifiable release artifact | Ready with notes | The rehearsal build runs anywhere. Developer ID signing and notarization need the maintainer's certificate and notary profile. |
| E7-S3 Update check | Ready with notes | New module and one network file; needs the Epic 6 allowlist. The real feed can only be checked once a release exists. |
| E7-S4 Crash recovery | Ready | A marker file is enough; nothing sensitive is stored. |
| E7-S5 Support diagnostics | Ready | Extends the Epic 6 schema test on purpose. |
| E7-S6 Accessibility | Ready with notes | The XCUITest audit needs a GUI session with UI Automation Mode; VoiceOver speech is manual. |
| E7-S7 Localization readiness | Ready with notes | The catalog today has no extracted strings; most work is extraction and a bundle check. |
| E7-S8 Compatibility suite and quality gate | Ready with notes | Real app behavior stays in the manual matrix; fakes model the behavior classes. UI tests stay non-blocking until proven stable. |
| E7-S9 Beta and rollback docs | Ready | Rollback walk-through uses draft or pre-release entries only. |

No blockers for development. Epic 7 needs Epic 6's network and security
allowlists and its Privacy pane, so it is developed on top of the Epic 6 branch
and merged after it. Parts of the exit criteria cannot be proven without the
maintainer's Apple credentials and are listed under *Needs the maintainer*.

## Checklist (epic level)

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Install, update, recover, get help, roll back. |
| 2 | Size | Pass | Nine stories; two at 8 points. |
| 3 | Dependencies | Concern | Needs Epic 6 (allowlists, Privacy pane, report schema). |
| 4 | Acceptance criteria | Concern | Notarization and Gatekeeper results cannot be shown on CI. |
| 5 | CI testability | Concern | Scripts, parsing, state, and fakes run on CI. Signing identity, notary service, GUI audit, and VoiceOver do not. |
| 6 | Privacy | Pass | The updater sends the app version only; it never downloads or runs code. |
| 7 | Permissions | Pass | No new permission. |
| 8 | Feasibility | Concern | The release job depends on the `xcode-27` hosted image; archive and export work offline. |
| 9 | Out of scope | Pass | No translated UI, no Store submission, no auto-install. |
| 10 | Open decisions | Concern | See below. |

## Decisions to record (proposed defaults)

1. **Channel** — Developer ID direct distribution, as assumed by ADR 0001. The
   Mac App Store needs the App Sandbox; whether Accessibility insertion can work
   there is unproven, so this stays the recommended path until an experiment says
   otherwise.
2. **Updates** — a user-started check against the GitHub latest-release endpoint
   and a manual download from the release page. No third-party updater now; the
   app never downloads or executes code, which removes the update channel as an
   attack path. Revisit Sparkle before 1.0 if seamless install is required.
3. **New module** — `Updates` (depends on Domain and Support). It is the second
   file on the network allowlist.
4. **Pre-releases** — ignored by the check unless the running build is one.
5. **Weekly check** — off by default; never during a session.
6. **Release job on CI** — a rehearsal build signed ad hoc, run on pushes to
   `main`; non-blocking at first, with the rule to make it required stated.
7. **UI tests** — required after seven consecutive green runs on the hosted runner.
8. **Crash handling** — local marker and notice; no crash upload.
9. **Localization** — ready, not translated: String Catalog, comments,
   formatters, pseudo-language checks.
10. **Gate** — `make quality-gate` is the single local entry point; CI runs the same steps.

## Needs the maintainer (cannot be done or proven here)

- A Developer ID Application certificate and a stored `notarytool` profile, to
  produce and notarize a real build and to run `spctl` on a clean Mac.
- A Mac on macOS 26.0 to confirm the minimum version.
- The App Sandbox experiment for the channel decision.
- A published release, to check the update feed against the real endpoint.
- Approval of ADR 0026 and the performance thresholds.

## AC → verification map

| Acceptance area | Verification |
|---|---|
| Channel and updater decision | ADR 0026 review; manual step for the Sandbox experiment |
| Release artifact | `scripts/tests/test-verify-release.sh`, `make release-build release-verify` (rehearsal) |
| Notarization | `scripts/notarize-release.sh` dry-run test; real run by the maintainer (manual) |
| Update check | `SemanticVersionTests`, `GitHubReleaseFeedTests`, `UpdateCheckerTests`, `UpdatesUITests` |
| Crash recovery | `LaunchSentinelTests`, `CrashRecoveryEndToEndTests`, manual force-quit step |
| Support diagnostics | `SupportInfoTests`, `DiagnosticsReportSchemaTests`, `DiagnosticsPrivacyTests` |
| Accessibility | `AccessibilityUITests` (audit), VoiceOver manual script |
| Localization | `scripts/check-localization.sh`, `LocalizationFormattingTests`, `PseudoLocalizationUITests` |
| Compatibility and gate | `CompatibilityProfileTests`, `scripts/tests/test-quality-gate.sh`, `make quality-gate` |
| Beta and rollback | `scripts/check-doc-links.py`, rollback walk-through in the PR |
