# Beta program

How LemmeType is tested with real people before a stable release, and how feedback
is handled. Releases are direct downloads ([ADR 0026](../decisions/0026-distribution-and-updates.md));
a beta is a GitHub pre-release tagged `vX.Y.Z-beta.N`.

## Who tests

- Friends and colleagues the maintainer invites, each on a Mac with Apple silicon on
  macOS 26 or later. Aim for a spread: 8 GB and 16 GB, Apple Intelligence on and off,
  English and at least one other dictation language, and the apps in the
  [insertion matrix](../testing/insertion-matrix.md).
- Testers are asked to run the first-run flow on a clean user account, because
  permissions and onboarding are the most fragile part.

## How a tester installs and updates

1. Download the pre-release `.zip` from the project's Releases page and check it
   against `SHA256SUMS`.
2. Move LemmeType to Applications and open it. macOS shows the usual first-open
   confirmation for a notarized app; there should be no other warning.
3. To update: Settings › General › Check for Updates…. The app opens the release page in
   the browser; the tester downloads the new build and replaces the old one. Pre-releases
   are offered only to people already on a pre-release.

## How a tester gives feedback

- **Settings › General › Report a Problem…** opens a GitHub form with the version, build,
  macOS version, and Mac model already filled in
  ([beta-feedback.yml](../../.github/ISSUE_TEMPLATE/beta-feedback.yml)).
- A tester who prefers not to use GitHub emails the maintainer the text from **Copy
  Support Info**.
- **Never send:** recordings, dictated text, or screenshots showing private text. The form
  says so and requires a checkbox. If a developer needs more, they ask for a diagnostics
  report saved from Settings › Diagnostics (the tester reads the preview first).

## Triage

Labels: `beta-feedback` on every report; severity comes from the dropdown in the form.

| Severity | Meaning | First reply within | Fix target |
|---|---|---|---|
| Blocker | Cannot dictate at all, data lost, or a privacy promise broken | 1 day | Next beta, or withdraw the release ([rollback](rollback.md)) |
| Major | A main feature fails | 3 days | Next beta |
| Minor | Wrong but there is a way around it | 1 week | Next release |
| Idea or question | | 1 week | Backlog, or answered |

A privacy or security report is a Blocker until shown otherwise and is handled before
anything else.

## Exit criteria for a stable release

- No open Blocker or Major reports from the current beta.
- Two consecutive betas with no new Blocker.
- The [privacy release checklist](../security/privacy-release-checklist.md) is complete.
- `make quality-gate` is green, and the manual checklist is run on a clean account
  ([manual-acceptance.md](../testing/manual-acceptance.md)).
- The product owner has approved the performance thresholds
  ([performance-thresholds.md](../testing/performance-thresholds.md)).
- The release notes follow the [template](release-notes-template.md).
