# Friends beta readiness — English only (2026-11-04)

Scope: the first friends beta of LemmeType (macOS, iPhone) and MeetQyl (macOS), English
only. MeetQyl's own copy of its part is `docs/release/friends-beta-readiness.md` in
`bkareti/LocalMeetTranscript`.

## Verdict

| App and platform | Verdict | Why |
|---|---|---|
| LemmeType, macOS | **Not yet release-ready.** Ready for a small, hand-held round once the manual checks pass | Code, privacy controls, and safeguards are in place and tested; release candidate builds and verifies. Missing: notarization (no Developer ID), the manual first-run and insertion checks on a clean account, and an approved threshold on 8 GB hardware |
| LemmeType, iPhone | **Not release-ready** | Quick Dictation + Copy is built and tested on the Simulator. TestFlight needs a paid Apple Developer Program membership; no physical-device evidence (MA-66…MA-72). The keyboard handoff is not approved (E8-S10/S14 gates) |
| MeetQyl, macOS | **Not yet release-ready.** Closest of the three | Beta features (LM-901…910) are merged, CI is green, a time-limited DMG builds and checks. Missing: the LM-901 acceptance recording on macOS 27 with the shared DMG, the full manual test matrix, and the feedback address |
| MeetQyl, iPhone | **Out of scope** | No iPhone target exists; Epic 13 is not started |

## Gaps

### P0 — blocks recording, transcription, privacy, or the core journey

| # | App | Gap | Status | Evidence |
|---|---|---|---|---|
| P0-1 | LemmeType (both) | Whisper wrote invented text from noise and tones, which would be typed at the cursor (#135) | **Fixed** (ADR 0028: no-speech gate, non-speech token suppression) | `NoSpeechGateTests`, `WhisperEngineTests`; English edge cases below |
| P0-2 | LemmeType (both) | Repetition loops in long dictation (#136) | **Fixed** (ADR 0028: loop guard keeps one copy of a phrase repeated 4+ times) | `RepetitionLoopTests` |
| P0-3 | MeetQyl | LM-901 acceptance: a 5-minute recording, relaunch, transcript, and playback with the shared DMG on macOS 27 | **Not done** — needs a person, microphone and system-audio permissions | ADR-0029 evidence lists it as not yet done |

### P1 — required for a dependable friends beta

| # | App | Gap | Status |
|---|---|---|---|
| P1-1 | LemmeType (both) | Hindi, Telugu, Automatic detection, translation, and 3 multilingual model downloads (up to 852 MB) were offered in an English-only beta | **Fixed** (ADR 0029, `LanguageScope`; Release builds only) |
| P1-2 | MeetQyl | Meeting languages and per-meeting language menus offered in an English-only beta | **Fixed** (LM-912; `Release-Direct` only) |
| P1-3 | LemmeType | The benchmark counted "7:45" vs "seven forty five" as errors (numeric WER 46 %), so English looked worse than it is | **Fixed**: reports now include number-normalized WER; thresholds unchanged pending approval |
| P1-4 | LemmeType | No tester guide, tester privacy explanation, or known-limits list | **Fixed**: `docs/release/friends-beta-guide.md` |
| P1-5 | MeetQyl | 0.2.0 version and notes missed the meeting assistant and the English-only limit | **Fixed** (version 0.2.0 build 2, CHANGELOG) |
| P1-6 | LemmeType | No Developer ID certificate or notary profile on the build Mac, so builds are ad hoc | **Blocked — maintainer** (see "Remaining blockers") |
| P1-7 | LemmeType | Performance thresholds were never recorded on hardware | **Partly**: first run on Mac16,1 below; minimum hardware (8 GB M1) and approval still open |
| P1-8 | Both | Manual acceptance on a clean account: first run, permissions, insertion into real apps (LemmeType MA-*, insertion matrix), MeetQyl test matrix | **Not run** — needs a person |
| P1-9 | MeetQyl | Feedback address (`BETA_FEEDBACK_EMAIL`) is empty, so Help › Send Feedback is hidden | **Decision — maintainer** |
| P1-10 | LemmeType iPhone | TestFlight distribution | **Blocked — Apple Developer Program** |
| P1-11 | MeetQyl | Plausible but wrong text passes quality checks (#95) | **Mitigated** (uncertain lines marked, LM-304); real-meeting accuracy still unmeasured |

### P2 — after the beta

- Shared transcription package (ADR 0030 / MeetQyl ADR-0033, Proposed).
- LemmeType keyboard handoff and Control Center flow (E8-S10…S16, physical-device gates first).
- A multilingual model installed before ADR 0029 is no longer listed in Settings › Models (still used and still removed by Delete All Local Data).
- MeetQyl AI clients on macOS 27 (needs a Team ID, LM-911).
- Automatic updates for either app.

### Future (not this release)

- Hindi, Telugu, and other Indian languages (#137, #138), translation to English, MeetQyl LM-1108 languages — behind the language scope until each is validated.
- MeetQyl iPhone (Epic 13), Android, Windows.

## Shared components

None moved in this release, on purpose: the two apps use different engines (whisper.cpp,
WhisperKit + SpeakerKit) and moving code before the beta adds risk without a user-visible
gain. ADR 0030 (here) and ADR-0033 (MeetQyl) propose a separate `LocalSpeechKit` package,
phase 1 = scoring rules, phase 2 = engine contract and model pinning, language packs later.
The English-only scope (`LanguageScope` here, `isEnglishOnlyRelease` in MeetQyl) is the
extension point for future language packs.

## Automated evidence (2026-11-04, Mac16,1, 16 GB, macOS 27.0)

| Check | LemmeType | MeetQyl |
|---|---|---|
| Lint / format | `make lint` passed | `make ci` (lint, format-check) passed |
| Package tests | `make test-unit` passed (all suites) | `make test` passed (module rules + ~1,170 tests) |
| App build | Release archive built | Debug build passed in `make ci` |
| Hosted app tests | **Not run**: the test host quit because a Debug LemmeType was already running on this Mac (single-instance rule) | n/a |
| UI tests | **Not run**: UI Automation Mode needs interactive authentication here | **Not run** |
| iOS | `make build-ios`, `make test-ios` passed (Simulator) | n/a |
| Localization | `make l10n-check` passed | n/a |
| Release candidate | `make release-build REHEARSAL=1` + `release-verify` passed: signature valid (deep, strict), Hardened Runtime, entitlements = allowlist, no get-task-allow, no recordings or transcripts inside. Notarization skipped (ad hoc). `-DENGLISH_ONLY_RELEASE` confirmed in the archive log | `make test-dmg VERSION=0.2.0 EXPIRES=2026-12-04` (see MeetQyl report) |

### English accuracy and speed (LemmeType, Whisper, this Mac)

| Measure | Whisper Small English (`whisper-small-en`) | Whisper Small multilingual (`whisper-small`, comparison only) |
|---|---|---|
| Sessions failed | 0 of 80 | 0 of 80 |
| Capture stop → text, mean / p95 | 0.50 s / 0.84 s | 0.45 s / 0.71 s |
| Real-time factor, mean | 0.11× | 0.10× |
| Model load (warm-up) | 0.20 s | 0.26 s |
| Memory added by the model | 686 MB | not measurable in the same process (peak already reached) |
| WER, clean (raw / numbers normalized) | 15.1 % / **10.3 %** | 16.3 % / 11.5 % |
| WER, noisy 10 dB (raw / numbers normalized) | 17.7 % / **12.9 %** | 20.9 % / 16.1 % |
| Conversational / technical / long (normalized) | 0.0 % / 0.4 % / 0.0 % | 0.0 % / 3.0 % / 0.0 % |
| Numeric (raw / normalized) | 46.0 % / **32.5 %** | 47.4 % / 33.9 % |
| Accent WER, raw: US / UK / Australian / Indian | 14.7 / 14.7 / 14.7 / 16.1 % | 16.3 / 14.7 / 16.7 / 17.5 % |
| English no-speech edge cases (silence, noise, tones): text produced | **0 of 8** (was 3 of 8 before ADR 0028) | not run |

Raw WER fails the Proposed `wordErrorRate` thresholds (≤ 10 % Small, ≤ 12 % overall) only
because of number formatting; every non-numeric category is at or below 3 %. Numbers stay
the weakest category even after normalization: currency, clock times, percentages, and
ordinals ("$420.50", "7:45", "18%", "12th") are not all folded by `NumberNormalizer`, and
some may be real mistakes. The benchmark keeps no text, so this was not inspected case by
case. Release builds list only the English models, so the multilingual column is for
comparison.

Notes:

- Corpus: `docs/testing/benchmark-corpus.json` v2 — 16 sentences (conversational,
  technical, numeric, long) in synthesized US, UK, Australian, and Indian English plus a
  noisy copy (10 dB SNR). Synthesized speech is cleaner than real speech: treat these as
  an upper bound on accuracy.
- Base (the 8 GB recommendation) was not installed on this Mac, so it was not measured.
- Real English recordings (FLEURS `en_us`) are not in the local corpus cache; fetching
  them needs your OK (a download from huggingface.co).
- Not measured: 8 GB M1 (the minimum), real meetings, overlapping speakers, very long
  meetings in MeetQyl (see MeetQyl ADR-0031 for its own measurements).

## Proposed beta acceptance thresholds (English)

Based on the run above; **Proposed until you approve them**.

| Metric | Beta bar | Measured here |
|---|---|---|
| No-speech audio that produces text | 0 of the English edge cases | 0 of 8 |
| Failed sessions in the benchmark | 0 | 0 |
| WER, numbers normalized, clean synthesized speech (Small English) | ≤ 12 % | 10.3 % |
| WER, numbers normalized, noisy (10 dB) | ≤ 20 % | 12.9 % |
| Capture stop → text, p95 (Small English, 16 GB) | ≤ 1.5 s | 0.84 s |
| Indian English accent WER vs US | within 3 points | 1.4 points (16.1 vs 14.7 %) |
| Numeric category WER, numbers normalized | tracked, no gate (known limit) | 32.5 % |
| Network sockets during dictation | 0 | Evaluation run's socket watch passed; MA-31 (live app) not rerun |

## Remaining blockers that need you

1. **Run the manual first-run and insertion checks** on a clean macOS user account with the
   release candidate (`docs/testing/manual-acceptance.md`, insertion matrix), and MeetQyl's
   test matrix with a real 5-minute call on macOS 27.
2. **Quit your running Debug LemmeType** (or let me) and rerun `make test-app`; run
   `make test-ui` from an interactive session.
3. **Signing:** join the Apple Developer Program for a Developer ID (macOS notarization) and
   TestFlight (iPhone). Without it, friends use **Open Anyway** and must re-enable
   Accessibility after every LemmeType update.
4. **Approve** the thresholds above (and `performance-thresholds.md`), ADR 0029, and decide
   on ADR 0030.
5. **MeetQyl feedback address:** set `BETA_FEEDBACK_EMAIL` in `Config/Signing.local.xcconfig`.

## How to give the beta to friends (today, without a Developer ID)

1. Merge the PRs (LemmeType: decoding safeguards, then English-only beta; MeetQyl: LM-912).
2. LemmeType: `make release-build REHEARSAL=1 && make release-verify REHEARSAL=1`, then
   send `build/release/LemmeType-<version>.zip` with its line from `SHA256SUMS` and
   `docs/release/friends-beta-guide.md`.
3. MeetQyl: follow its release checklist (tag `v0.2.0`, then its `test-dmg` and
   `check-dmg` make targets with the last day you choose), and send the DMG, its install
   guide, and its beta README (all in `bkareti/LocalMeetTranscript`).
4. Start with 3–5 friends on Apple silicon; collect reports with the labels `beta-feedback`
   (LemmeType) and `beta` (MeetQyl).
5. **Rollback:** LemmeType `docs/release/rollback.md`; MeetQyl: ask testers to reopen the
   previous DMG (their meetings stay on the Mac). A test DMG also stops on its last day.
