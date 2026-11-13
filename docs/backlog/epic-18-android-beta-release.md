# Epic 18 — Android privacy hardening, beta, and Play release

## Epic issue body

### Objective

Make the Android app ready for testers and then the public: device-proven privacy,
accessibility, approved thresholds, a signed release pipeline, a closed beta that meets
Google Play's rules, and a staged production rollout with a rollback plan
([plan](../android/android-plan.md) Phases 7–8).

### Business value

A careful release keeps the privacy promise credible and protects the Apple apps' reputation.
Play's closed-test rule for new personal accounts (12+ testers for 14 days) also makes the
beta a required step, not an optional one.

### In scope

- Privacy hardening and the Android threat model; optional isolated recognition process.
- Accessibility, localization readiness, large screens and foldables.
- The device matrix and threshold approval.
- Signing, AAB, Play Console setup, Data safety, foreground-service declaration, store listing.
- Internal and closed testing, feedback, production staged rollout, monitoring, rollback.

### Out of scope

- Third-party crash or analytics SDKs (Play vitals only).
- Distribution outside Google Play (other stores, direct APK) — a later decision.

### Epic acceptance criteria

- All child stories are accepted.
- Thresholds per device class are approved by the product owner.
- The closed test met Play's requirement and its feedback is triaged.
- Production rollout reached 100 % with crash-free and ANR rates within Play's bad-behaviour thresholds, or was halted and rolled back by the documented process.

---

## E18-S1 — Harden privacy and complete the Android threat model

**Objective:** device-level proof of the privacy claims.

**User story**

As a user, I want independent-looking evidence that LemmeType does what it says, on a real phone.

**Scope**

- Device checks: no socket during a full dictation (`adb shell cat /proc/net/tcp6` for our uid, `TrafficStats`, Android's per-app data usage); no audio after force stop; backup/transfer excludes private files.
- Spike + decision: run Whisper in an `android:isolatedProcess` service (no permissions of its own) with audio passed through a pipe. Adopt only if the latency cost is ≤ 10 %.
- Threat model rows A-01 … A-15 final, each with a real check; `make privacy-docs-check` covers them.
- Android privacy release checklist section.

**Acceptance criteria**

- Device checks recorded in `android-feasibility.md` (MA steps).
- Isolated-process decision recorded (adopted or not, with numbers).
- `make privacy-docs-check` passes.

**Dependencies:** E14-S16, E14-S14 (E15 if the keyboard ships)  
**Automated verification:** privacy scripts, socket and canary tests.  
**Physical-device verification:** the checks above on two phones.  
**Estimate:** 5 points (Medium)

---

## E18-S2 — Accessibility, localization readiness, and large screens

**Objective:** usable by everyone, on every screen size.

**User story**

As a TalkBack user, or someone on a tablet or foldable, I want LemmeType to work as well as
it does for anyone else.

**Scope**

- TalkBack labels and order, touch targets ≥ 48 dp, contrast, font scaling to 200 %, dark theme.
- All strings in `strings.xml` with translator comments; lint fails on hard-coded strings.
- Adaptive layouts (Android 16 ignores orientation locks on large screens for target 36); configuration change during recording keeps the session.

**Acceptance criteria**

- Accessibility scanner and Compose semantics tests pass.
- Rotation and fold during recording keep the session (instrumentation test).
- No hard-coded user-facing strings (lint).

**Dependencies:** E14-S14 (E15-S2 if the keyboard ships)  
**Automated verification:** lint, Compose tests, Espresso accessibility checks.  
**Physical-device verification:** TalkBack run on one phone; tablet and foldable layouts.  
**Estimate:** 5 points (Medium)

---

## E18-S3 — Fill the device matrix and approve thresholds

**Objective:** numbers per device class that the product owner signs off.

**User story**

As the product owner, I want accuracy, latency, memory, and battery measured on the phones
our testers own so that I release only what meets the bar.

**Scope**

- Plan section 11 matrix; lifecycle and failure matrix; host-app matrix.
- Measurements: stop-to-text, keyboard tap-to-recording, peak memory, battery for 10 dictations, WER (E17-S1 harness).
- Threshold file (`docs/testing/android-performance-thresholds.json`, Proposed → Approved) and a check script like `check-performance-thresholds.py`.

**Acceptance criteria**

- Every required device row is filled with date, Android version, and tester initials.
- The product owner approves the thresholds in the PR.
- Any failing class is excluded from the beta's supported list (store listing and in-app message).

**Dependencies:** E14-S15, E16-S5, E17-S1 (E15-S6 if the keyboard ships)  
**Automated verification:** threshold check script with fixtures.  
**Physical-device verification:** the matrix.  
**Estimate:** 5 points (Medium)

---

## E18-S4 — Release pipeline and Play Console setup

**Objective:** a repeatable signed release and a store entry that tells the truth.

**User story**

As the maintainer, I want one command that builds a verified release bundle, and a Play
listing whose privacy answers match the code.

**Scope**

- Version in one place (`android/version.properties`); version code strictly increasing.
- `make android-release`: signed AAB with the upload key (maintainer's machine; key never in the repository or CI for beta), R8, 16 KB alignment check, manifest and dependency checks, `bundletool` validation.
- `scripts/verify-android-release.sh`: permissions, exported components, debuggable false, no test fakes, native alignment.
- `docs/release/play-store.md`: account steps, Play App Signing, listing text, screenshots process, content rating, Data safety answers (nothing collected in Local-only builds; cloud answers when E17 ships), foreground-service declaration text and demo video plan, review notes.

**Acceptance criteria**

- Release verify script has fixture tests and passes on the release AAB.
- An internal-testing upload succeeds (maintainer action).
- Data safety answers are reviewed against the manifest and network allowlist in the PR.

**Dependencies:** E14-S16, E18-S1  
**Automated verification:** verify script; `make android-check`.  
**Physical-device verification:** install from internal testing on two phones.  
**Estimate:** 5 points (Medium)

---

## E18-S5 — Run the closed beta

**Objective:** real users, small group, meeting Play's rule for production access.

**User story**

As a tester, I want an easy way to join, clear instructions, and a way to report problems
without sending my dictations.

**Scope**

- Closed track; 15–20 testers (≥ 12 opted in for 14 consecutive days if the account is a new personal account).
- Tester guide (Android version of `docs/release/friends-beta-guide.md`): what works, what does not, how to report.
- In-app "Copy support info" (versions, device class, settings identifiers; no content).
- Feedback triage into issues; crash and ANR review in Play vitals weekly.

**Acceptance criteria**

- Tester count and dates recorded; Play production access requested and granted (maintainer).
- Every crash cluster in Play vitals has an issue.
- No tester report contains dictated content (guide says so; triage removes it if it appears).

**Dependencies:** E18-S3, E18-S4  
**Automated verification:** support-info schema test (identifiers only).  
**Physical-device verification:** testers' devices (recorded by class, not by person).  
**Estimate:** 3 points (Small)

---

## E18-S6 — Production rollout, monitoring, and rollback

**Objective:** release in steps, watch, and be able to go back.

**User story**

As the maintainer, I want a staged rollout with clear stop rules so that a bad build reaches
as few people as possible.

**Scope**

- Staged rollout 5 % → 20 % → 50 % → 100 %, at least 48 h per step.
- Stop rules: user-perceived crash rate or ANR rate above Play's bad-behaviour threshold, any privacy report, or a threshold regression.
- Rollback runbook (`docs/release/android-rollback.md`): halt rollout, ship the previous code with a higher version code, notify testers.
- Post-release checklist: Data safety still accurate, target SDK deadline tracked, 16 KB check, policy announcements reviewed.

**Acceptance criteria**

- Rollback rehearsed once on the internal track and recorded.
- Rollout reaches 100 % or is halted per the rules, with the decision recorded.

**Dependencies:** E18-S5  
**Automated verification:** none beyond release checks.  
**Physical-device verification:** update from the previous version on two phones keeps settings and models.  
**Estimate:** 3 points (Small)

---

## Epic 18 story order

1. E18-S1
2. E18-S2
3. E18-S3
4. E18-S4
5. E18-S5
6. E18-S6
