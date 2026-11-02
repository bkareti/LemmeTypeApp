# Compatibility matrix and quality gate (E7-S8)

What "works" means, where it is checked automatically, and where a person has to
look. Real applications are in [insertion-matrix.md](insertion-matrix.md); this page
lists the behaviour classes they fall into, which the tests can model.

## Supported platform

| Dimension | Supported | Checked by |
|---|---|---|
| macOS | 26.0 and later, Apple silicon (ADR 0001) | CI builds on the hosted `xcode-27` image; **macOS 26.0 itself needs a Mac on that version** (`MA-65`) |
| Memory | 8 GB (minimum) and 16 GB or more | `PerformancePlanTests`, `ModelFitTests`; real hardware: `MA-45`, `MA-46` |
| Apple Intelligence | On (rewriting works) and off or unsupported (rewriting is refused with a reason) | `FoundationModelsRewriterTests` with a fake; real Macs: `MA-53` |
| Languages | English validated; Hindi and Telugu evaluation (ADR 0023) | `LanguageSupportMatrixTests`, `MultilingualEndToEndTests`; `MA-47` to `MA-50` |
| Accessibility settings | VoiceOver, Reduce Motion, full keyboard access | `AccessibilitySourceTests`, `AccessibilityUITests`; `MA-63` |

## Application behaviour classes (automated)

Each class is run through the whole local loop in `CompatibilityProfileTests`
(recorder → pipeline → delivery → a fake field). A change that breaks one fails CI.

| Profile | Example apps | What the field does | Expected result | Test |
|---|---|---|---|---|
| P1 | Notes, Mail, TextEdit, Messages | Takes Accessibility writes | Typed once through Accessibility | `p1AccessibilityWritableField` |
| P2 | Electron apps, Word | Says yes but ignores the write | Paste, then the clipboard is restored | `p2FieldThatIgnoresAccessibilityWrites` |
| P3 | Some web views, custom editors | Refuses selected-text writes | Paste fallback | `p3FieldThatRefusesSelectedTextWrites` |
| P4 | Unusual editors | The write call fails | Paste fallback | `p4FieldWhoseWriteFails` |
| P5 | Fields that hide their length | Accepts the write | Typed once; the accepted write is trusted | `p5FieldThatCannotBeCountedButAcceptsTheWrite` |
| P5b | The same, without an answer | Gives no answer at all | **No second attempt** (it could type twice); Copy is offered | `p5bFieldThatCannotBeVerifiedGetsNoSecondAttempt` |
| P6 | Password fields | Secure text field | Nothing typed; Copy is offered | `p6SecureFieldNeverReceivesText` |
| P7 | Any app | The user moves to another field while processing | Nothing typed anywhere; Retry Insert and Copy | `p7FocusMovesAway` |
| P8 | Any app | Accessibility trust is missing | Nothing typed; the recorder asks for attention | `p8AccessibilityNotTrusted` |
| P9 | Slack, VS Code | No readable text range | Dictation still works; context formatting is skipped | `p9FieldWithoutReadableTextRanges` |
| P10 | Password managers, excluded apps | Sensitive or excluded app | Nothing around the cursor is read | `p10SensitiveAndExcludedAppsAreNotRead` |

## Manual rows

| Check | Step |
|---|---|
| Real apps: Mail, Messages, Notes, Safari, Chrome, Word, Slack, VS Code | `MA-28`, `MA-29`, [insertion-matrix.md](insertion-matrix.md) |
| Real Developer ID build opens on a clean Mac | `MA-59` |
| The update check against the real feed | `MA-60` |
| macOS 26.0 minimum | `MA-65` |

## The quality gate

`make quality-gate` runs every automated check and prints one summary. CI runs
the same steps (a test compares them), grouped into jobs:

| Step | Command | CI job | Required |
|---|---|---|---|
| Lint | `make lint` | build-and-test | Yes |
| Build | `make build` | build-and-test | Yes |
| Package tests | `make test-unit` | build-and-test | Yes |
| Hosted app tests | `make test-app` | build-and-test | Yes |
| No leftover audio | `make privacy-check` | build-and-test | Yes |
| Network allowlist | `make network-check` | build-and-test | Yes |
| Security allowlists | `make security-check` | build-and-test | Yes |
| Threat model and checklist | `make privacy-docs-check` | build-and-test | Yes |
| Localization | `make l10n-check` | build-and-test | Yes |
| Release and support documents | `make docs-check` | build-and-test | Yes |
| Release scripts | `make release-script-tests` | release-readiness | No (until a week of green runs) |
| UI tests | `make test-ui` | ui-tests | No (see below) |

**UI tests become required** after seven consecutive green runs of the `ui-tests`
job on the hosted runner. Until then they run on every change but do not block
merging. Locally they need a GUI session with UI Automation Mode; `make
quality-gate UI=1` includes them. A step that is skipped is printed as skipped,
never as passed.

**Coverage** is printed for information (`scripts/coverage-summary.sh`). No
threshold fails the build yet: *Proposed* floor, pending the product owner —
Domain 90 %, others measured first.

**Flaky tests:** a test that fails and then passes without a code change is fixed
or removed within the week; wait on state (`waitUntil`, `settle()`), never on a
fixed sleep.
