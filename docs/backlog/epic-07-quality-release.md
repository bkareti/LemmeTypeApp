# Epic 7 — quality, packaging, and release readiness

## Epic issue body

### Objective

Make LemmeType something a person can install, trust, update, and get help with,
and something the team can ship and roll back without guessing.

### Business value

Epics 1 to 5, 9, and 10 built the product. A person can only use it if the
download is signed and notarized, macOS does not warn about it, they can learn
about a new version, and the app recovers when something goes wrong. The team
needs one quality gate and a rehearsed rollback so that a bad build is a small
incident instead of a crisis.

### In scope

- A recorded decision on direct distribution versus the Mac App Store, and on
  how updates work, with a prototype of the chosen path (ADR 0026).
- A repeatable release pipeline: archive, hardened runtime, signature and
  entitlement checks, zip and disk image, checksums, and notarization and
  stapling when credentials are present.
- An in-app update check that the user starts (and may switch to weekly),
  that sends only the app version, and that never downloads or runs code.
- Recovery after a crash or forced quit, with a clear notice.
- Support diagnostics: an About section, a fuller but still private report, and
  a safe way to report a problem.
- Accessibility checks (automated audit, keyboard use, VoiceOver steps).
- Localization readiness (string catalog, pseudo-language checks, formats).
- A compatibility suite and one quality gate that runs every automated check.
- Documented beta feedback, release notes, and release rollback processes.

### Out of scope

- Shipping a translated user interface (this epic makes the app ready, it does
  not add languages).
- Submitting to the Mac App Store, or running the App Sandbox.
- Automatic download or installation of updates, and a third-party updater.
- Crash upload, telemetry, or any analytics (Epic 6 forbids them).
- Buying or provisioning Apple Developer ID certificates and notary
  credentials. The pipeline reads them from the maintainer's Keychain.
- iPhone and iPad (Epic 8).

### Epic acceptance criteria

- All child stories are accepted.
- The distribution and update decision is recorded and approved by the product
  owner, with evidence for the chosen path and the gaps listed for the other.
- A rehearsal release build passes the verification script on a Mac; a real
  Developer ID build is signed, hardened, notarized, and stapled by following
  the runbook (needs the maintainer's credentials).
- The update check works against a fake feed in automated tests and against the
  real feed once a release exists, and sends nothing but the version.
- A killed app starts cleanly, removes leftover temporary audio, and tells the
  user once.
- The accessibility audit passes for onboarding, every Settings pane, and the
  menu, with only justified exclusions.
- Every user-visible string is in the catalog; pseudo-language runs show no
  clipped or missing controls in the audited panes.
- `make quality-gate` runs every automated check and CI reports it.
- Beta feedback and rollback processes are written and the rollback has been
  walked through step by step.

---

## E7-S1 — Record the distribution channel and update mechanism

**User story**

As a product team, we want a recorded decision on how LemmeType is distributed
and updated, so that the pipeline and the updater are built once.

**Scope**

- ADR 0026 comparing Developer ID direct distribution with the Mac App Store,
  using the constraints in ADR 0001 (no App Sandbox for Accessibility
  insertion), review risk, update speed, and user trust.
- A comparison of update mechanisms: a user-started version check with a manual
  download from the release page, a third-party updater (for example Sparkle),
  and none. Include dependency, network behavior, key custody, and what code
  could ever be downloaded.
- The recommended default and the evidence still missing (for example, an App
  Sandbox experiment on a real Mac).
- The channel name used in diagnostics and the Privacy pane.
- The status of the ADR (Proposed until the product owner approves).

**Acceptance criteria**

- The ADR has a decision table with a recommendation for channel and updater.
- The ADR lists what is validated by the prototype (E7-S2, E7-S3) and what is
  not, with a manual step for the missing App Sandbox experiment.
- The ADR states how the network policy from Epic 6 applies to the updater.
- The release-management skill and `CLAUDE.md` point to the ADR.
- Open questions list a proposed default each.

**Dependencies:** ADR 0001, ADR 0025 (E6-S1)  
**Estimate:** 3 points

---

## E7-S2 — Build a release artifact you can verify

**User story**

As a maintainer, I want one command that builds a hardened release and one that
proves it is correct, so that nobody ships a build that macOS will reject.

**Scope**

- `Config/ExportOptions-DeveloperID.plist` and `scripts/build-release.sh`:
  archive the Release configuration, export with Developer ID when an identity
  is available, otherwise produce a clearly labelled *rehearsal* build signed
  ad hoc. Zip with `ditto`, build a disk image, and write SHA-256 checksums.
- `scripts/verify-release.sh`: checks the bundle identifier, version and build
  against `Config/Version.xcconfig`, arm64 only, minimum macOS, `LSUIElement`,
  usage strings, code signature validity (deep and strict), Hardened Runtime
  flag, embedded frameworks signed, entitlements equal to the allowlist, and no
  `get-task-allow`. It then runs `check-release-artifact.sh`.
- `scripts/notarize-release.sh`: submit with `notarytool` using a Keychain
  profile, wait, staple, validate the staple, and run `spctl`. It stops with a
  clear "not notarized" message and exit code when no profile is set, and never
  prints credentials.
- Make targets `release-build`, `release-verify`, and `release-notarize`, and a
  CI job that runs the rehearsal and verification on every push to `main`.
- `docs/release/runbook.md` with the exact steps and where the maintainer's
  credentials go.

**Acceptance criteria**

- A rehearsal build completes on this Mac and passes `verify-release.sh`.
- `verify-release.sh` fails on each seeded violation: missing Hardened Runtime,
  extra entitlement, `get-task-allow`, wrong version, unsigned embedded
  framework, and a bundled recording (fixture tests).
- `notarize-release.sh` exits non-zero with a clear message when no profile is
  configured and is covered by a dry-run test.
- The runbook lists every command, the credentials needed, and the expected
  output of each step.
- The notarization and Gatekeeper result on a real Developer ID build is
  recorded in the PR or marked *Not verified* (it needs the maintainer's
  credentials).

**Dependencies:** E7-S1, E6-S7, E2-S10  
**Estimate:** 8 points

---

## E7-S3 — Check for updates without sending anything but the version

**User story**

As a user, I want LemmeType to tell me when a new version exists, only when I
ask, so that I stay up to date without background network traffic.

**Scope**

- A new `Updates` module (ADR 0026) with the only update-related network code:
  one HTTPS GET to the project's GitHub latest-release endpoint, using an
  ephemeral session with no cookies, cache, or credentials, and a fixed header
  set whose only app-specific value is the version in the user agent.
- Domain: `SemanticVersion`, `ReleaseInfo`, `UpdateChecking`, `UpdateStatus`,
  and `UpdateError` with stable identifiers. Pre-releases are ignored unless the
  user is already on one.
- Settings › General › Updates and a menu item: Check for Updates…, the result,
  Download Page… (opens the release page in the browser; the app downloads and
  runs nothing), and "Check weekly", which is off by default.
- No check while a dictation session is active, and none unless the user asked
  or switched on weekly checks.
- Privacy copy that says what is sent (the version and, as with any web
  request, the IP address).
- The network allowlist from Epic 6 gains this one file, with a SwiftLint
  exception limited to it.

**Acceptance criteria**

- Version comparison handles major, minor, patch, build, and pre-release
  ordering (table-driven tests).
- A sample GitHub payload parses; a payload with a foreign host, a non-HTTPS
  link, or an oversized body is rejected (tests).
- A stubbed request carries only the allowed headers and no body or cookies.
- With the preference off and no click, a fake feed receives zero requests; a
  click or an overdue weekly check makes exactly one (fake clock).
- No request is made while a session is active.
- "No release published yet" and offline are shown as such, never as a crash.
- A UI test covers the button, result, and toggle with a fake feed.
- A manual step checks the real feed once a release exists.

**Dependencies:** E7-S1, E6-S2, E6-S5  
**Estimate:** 8 points

---

## E7-S4 — Recover cleanly after a crash or forced quit

**User story**

As a user, I want LemmeType to start normally after it crashed or was force
quit, and to tell me what happened, so that I am not left wondering.

**Scope**

- A launch sentinel (Lifecycle): a small marker written at launch and removed
  on a normal quit. If it is present at launch, the previous run ended
  unexpectedly.
- On an unexpected end: record a `lifecycle.unclean-exit` diagnostic, remove
  leftover session audio (already done at launch) and stale download staging,
  and show a one-time notice in the menu with a link to Settings › Diagnostics.
- The second instance of the app never writes or clears the marker.
- A note in the Diagnostics pane about macOS crash reports (they stay on the Mac;
  the user attaches one by hand if they choose).

**Acceptance criteria**

- First launch and launch after a normal quit show no notice.
- A leftover marker produces one diagnostic and one notice; dismissing it
  persists; the next normal launch shows nothing.
- An unreadable marker counts as an unexpected end and does not crash.
- Leftover session audio from a killed run is removed at the next launch
  (end-to-end test with a stale file).
- A second launch handed off to the first instance leaves the marker alone.
- A manual step force-quits the app mid-recording and checks recovery.

**Dependencies:** E1-S2, E1-S7, E6-S6  
**Estimate:** 5 points

---

## E7-S5 — Make support diagnostics easy to share safely

**User story**

As a user with a problem, I want to see what version I run and send helpful
information without sending my words, so that I can get help safely.

**Scope**

- Settings › General › About: version, build, distribution channel, macOS
  version, Mac model, and Copy Support Info.
- A richer report: schema version, channel, whether the previous run ended
  unexpectedly, installed model identifiers, language and output identifiers,
  performance profile, history retention as a name, and update-check setting.
  Still previewed before saving; still no upload.
- Report a Problem…: opens a prefilled GitHub issue that contains only the
  version, build, macOS version, and Mac model, and tells the user to attach the
  saved report by hand.
- A size limit for the report and the existing redaction rules.

**Acceptance criteria**

- Copy Support Info contains exactly the About fields (test).
- The report schema test from Epic 6 is updated deliberately for the new keys.
- The canary suite still finds no canary in the larger report.
- The issue link contains no field other than the four above (test of the URL).
- The report stays under a documented size with a full event buffer.
- Every new control has a label and an identifier.

**Dependencies:** E7-S3, E7-S4, E6-S6  
**Estimate:** 5 points

---

## E7-S6 — Verify accessibility

**User story**

As a user of VoiceOver or the keyboard, I want every part of LemmeType to be
usable and announced, so that I can dictate and configure it without a mouse.

**Scope**

- An XCUITest accessibility audit for onboarding, each Settings pane, and the
  menu, with a short list of justified exclusions.
- Keyboard checks: every Settings pane can be reached and every control focused
  with full keyboard access.
- A check that every interactive control has a non-empty label and identifier.
- Reduce Motion and contrast checks for the overlay and the review states.
- A manual VoiceOver script for a full dictation, a review, and an error.
- Fixes for what the audit finds.

**Acceptance criteria**

- The audit runs on every pane and passes with only documented exclusions.
- A UI test fails when a control without a label is added to an audited pane.
- Every state change that matters is announced (existing announcement tests
  stay green).
- The VoiceOver script is in the manual checklist with the expected speech.
- Any issue the audit finds is fixed or listed with an owner.

**Dependencies:** E1-S6, E6-S5, E7-S5  
**Estimate:** 5 points

---

## E7-S7 — Make the app ready for localization

**User story**

As a future translator, I want every user-visible string in the catalog with
context, so that adding a language needs no code changes.

**Scope**

- Complete `Localizable.xcstrings` for the UI module and the app target, with
  translator comments for ambiguous strings.
- Fix strings built by joining pieces, hard-coded user-visible text, and
  number, date, and byte-size formats that ignore the locale.
- `make l10n-check`: export localizations, fail when a string is missing from
  the catalog or marked stale, and when a user-visible literal bypasses the
  module bundle.
- UI checks with the double-length pseudo-language and a right-to-left layout
  that confirm the audited panes still show their controls.

**Acceptance criteria**

- The check fails when a new string is missing from the catalog or a view uses
  a literal that bypasses localization (fixture test).
- Dates, numbers, and sizes in history, models, and the review use formatters
  that follow the locale (tests with two locales).
- No concatenated sentence remains (search plus review in the PR).
- The pseudo-language run keeps every audited control present and hittable.
- The catalog has no empty comment on strings flagged ambiguous in the review.

**Dependencies:** E6-S5, E7-S6  
**Estimate:** 5 points

---

## E7-S8 — Add the compatibility suite and one quality gate

**User story**

As a maintainer, I want one command and one CI report that run every automated
check, and tests that model how different apps behave, so that a regression
cannot hide.

**Scope**

- `docs/testing/compatibility-matrix.md`: supported macOS versions, hardware
  classes, and application behavior profiles, and which row is automated.
- Automated profiles through the existing fakes: AX-writable field, field that
  ignores AX writes (paste), field without range text, read-only field,
  secure input, target that changed, and an app that is excluded.
- `make quality-gate`: lint, build, package tests, hosted app tests, privacy,
  network, security, privacy-docs, localization checks, and (when a GUI session
  exists) UI tests, with a one-screen summary and a non-zero exit code on any
  failure.
- CI runs the gate's automated steps and states which are required and which
  are non-blocking, with the rule for making UI tests required.
- A coverage summary printed for information.

**Acceptance criteria**

- Each automated profile has a named end-to-end test and a row in the matrix.
- `make quality-gate` runs every step listed, and its summary names any failure.
- The CI workflow lists the same steps as the gate (a check compares them).
- The UI test policy is written down: required after seven consecutive green runs.
- The manual rows of the matrix link to the checklist steps.

**Dependencies:** E6-S2, E6-S7, E6-S8, E7-S2, E7-S7  
**Estimate:** 5 points

---

## E7-S9 — Document beta feedback and release rollback

**User story**

As a maintainer, I want written processes for beta feedback and for withdrawing a
bad release, so that we respond the same way every time.

**Scope**

- `docs/release/beta-program.md`: who tests, how to install, how to give
  feedback without sending private content, triage labels and response times,
  and exit criteria for a stable release.
- A beta feedback issue template.
- `docs/release/rollback.md`: when to roll back, the exact GitHub Release
  steps, how the update check behaves after a withdrawal, how users go back,
  and the rule that data files are never overwritten by an older version.
- `CHANGELOG.md` (Keep a Changelog) and a release-notes template.
- The release-management skill and the README link to all of these.
- A rollback walk-through recorded in the PR using draft or pre-release
  entries only (nothing is published).

**Acceptance criteria**

- The documents exist and are linked from the README and the skill.
- The issue template parses and asks for the version and build but not for audio
  or text, and says so.
- A link check passes for every path the documents mention.
- The rollback steps name the commands, and the walk-through records what each
  command printed.
- The README status section is current.

**Dependencies:** E7-S2, E7-S3  
**Estimate:** 3 points

## Epic 7 story order

1. E7-S1
2. E7-S2
3. E7-S3
4. E7-S4
5. E7-S5
6. E7-S6
7. E7-S7
8. E7-S8
9. E7-S9
