# Epic 1 — macOS foundation, permissions, and audio capture

## Epic issue body

### Objective

Create the native macOS foundation that lets a user launch LemmeType, grant the
minimum permissions, invoke it from any application, and record microphone audio
through a clear and reliable state machine.

### Business value

Global activation and safe audio capture are the first technical risks. Until
they work reliably, transcription quality and intelligent writing features do
not create a usable system-wide product.

### In scope

- Native Swift/SwiftUI macOS project and test targets.
- Menu-bar lifecycle and settings window.
- Permission onboarding for Microphone and Accessibility.
- Configurable global shortcut with push-to-talk and toggle behavior.
- Microphone selection and audio capture.
- Recording overlay, cancellation, and recoverable errors.
- Privacy-safe diagnostics and foundation tests.

### Out of scope

- Speech recognition and transcript cleanup.
- Text insertion into other applications.
- Model downloads.
- Cursor context and selected-text editing.
- Cloud processing and user accounts.

### Epic acceptance criteria

- All child stories are accepted.
- A clean install can reach a successful test recording without developer tools.
- Recording never starts without visible state and never remains active after cancel, quit, sleep, or fatal capture error.
- No captured audio or sensitive field contents appear in logs.
- The foundation builds and tests on CI using the documented toolchain.

---

## E1-S1 — Scaffold the native macOS project and architecture

**User story**

As a developer, I want a reproducible native project with clear module boundaries
so that features can be implemented and tested without coupling UI, audio, and
platform services.

**Scope**

- Create the Xcode project/workspace and application target.
- Create unit and UI test targets.
- Establish modules or folders for App, Domain, Audio, Permissions, Shortcuts, UI, and Support.
- Add a dependency-composition root so platform implementations can be replaced by test doubles.
- Record the selected minimum macOS version, supported CPU architecture, Swift version, and Xcode version in an architecture decision record.
- Add build and test instructions to the README.

**Acceptance criteria**

- Given a clean checkout with the documented Xcode version, when the documented build command runs, then the app builds without manual configuration.
- Given the repository, when the test command runs, then unit and UI test targets are discovered and complete successfully.
- Given a developer inspects the application entry point, then concrete services are composed in one identifiable location.
- Given a test target, when an audio or permission dependency is needed, then it can be replaced without invoking the real operating-system service.
- The platform-baseline decision and rationale are committed under `docs/decisions`.

**Technical notes**

- Prefer Swift Package Manager and Apple frameworks unless a dependency has a documented product benefit.
- Do not introduce a speech or language-model dependency in this story.

**Dependencies:** None  
**Estimate:** 3 points

---

## E1-S2 — Implement the menu-bar lifecycle and settings entry points

**User story**

As a user, I want LemmeType to remain quietly available from the menu bar so
that I can dictate without keeping a normal application window open.

**Scope**

- Menu-bar icon and status menu.
- Open Settings, Start Test Recording, About, and Quit actions.
- Settings window that can be reopened after closing.
- Optional Launch at Login control using the supported macOS API.
- Single-instance behavior.

**Acceptance criteria**

- Given LemmeType launches, when no settings window is open, then the menu-bar item remains available.
- Given the menu is open, when Settings is selected, then exactly one settings window is activated.
- Given Launch at Login is enabled or disabled, when the app relaunches, then the UI reflects the system registration state.
- Given the user selects Quit while recording is idle, then the app exits cleanly.
- Given a second launch attempt, then it activates the existing instance rather than creating conflicting recorder state.

**Out of scope:** Final branding artwork and updater integration.  
**Dependencies:** E1-S1  
**Estimate:** 3 points

---

## E1-S3 — Build permission onboarding and permission-state recovery

**User story**

As a new user, I want to understand and grant only the permissions LemmeType
needs so that I can trust the app and complete setup without guessing.

**Scope**

- Explain Microphone and Accessibility separately before requesting them.
- Request Microphone permission in context.
- Detect Accessibility trust and open the correct System Settings pane when requested.
- Show live states: Not Requested, Granted, Denied, and Restricted/Unavailable.
- Recheck state when the app becomes active.
- Allow onboarding to continue in a limited state where safe.

**Acceptance criteria**

- Given a clean install, when onboarding starts, then no permission prompt appears before its explanation.
- Given Microphone is granted, when the user returns to onboarding, then its state changes to Granted without relaunching.
- Given Microphone is denied, then the app provides a working path to the relevant System Settings pane and does not repeatedly prompt.
- Given Accessibility is revoked while the app runs, when the app becomes active, then the displayed status updates and insertion-dependent features are marked unavailable.
- Onboarding does not request Screen Recording or Input Monitoring unless a later feature proves it is required.
- Permission status contains no claim that the operating system cannot guarantee.

**Dependencies:** E1-S1, E1-S2  
**Estimate:** 5 points

---

## E1-S4 — Register and configure the global recording shortcut

**User story**

As a user, I want a configurable shortcut that works while another application
is active so that I can start dictating without changing focus.

**Scope**

- Register a global shortcut.
- Support Push to Talk and Toggle modes.
- Validate and persist a user-selected shortcut.
- Detect conflicts or registration failure.
- Preserve the identity of the foreground application and focused UI element at activation time for later delivery.
- Provide a cancel action.

**Acceptance criteria**

- Given a valid shortcut and another app is active, when the shortcut activates, then LemmeType receives exactly one start event without taking keyboard focus.
- In Push to Talk mode, recording begins after key-down and ends after key-up.
- In Toggle mode, the first activation starts and the next activation stops.
- Given the shortcut cannot be registered, then the user sees a recoverable error and can choose another shortcut.
- Given repeated or bouncing key events, then the recording state machine does not create overlapping sessions.
- Activation captures a non-retained target reference sufficient for Epic 2 delivery without reading target text.

**Dependencies:** E1-S1, E1-S3  
**Estimate:** 5 points

---

## E1-S5 — Capture microphone audio through a testable audio service

**User story**

As a user, I want LemmeType to capture clear audio from my chosen microphone so
that local transcription has consistent input.

**Scope**

- Enumerate available input devices.
- Select System Default or a specific input and persist the choice.
- Capture mono PCM audio in a format accepted by planned recognition engines.
- Expose level metering without retaining audio samples in UI state.
- Handle device changes, disconnects, interruption, sleep, and wake.
- Store session audio in a protected temporary location and delete it on cancel.

**Acceptance criteria**

- Given Microphone permission and an available device, when recording starts, then audio buffers are delivered with documented sample rate, channel count, and encoding.
- Given the selected device is unavailable, then the service falls back to System Default or returns a typed, actionable failure.
- Given the device disconnects during capture, then recording stops safely and exposes a recoverable error.
- Given the user cancels, then capture stops and the temporary recording is deleted.
- Given an audio level is present, then the UI can display a meter without logging raw audio or sample values.
- Automated tests cover start, stop, cancel, interruption, and device-loss transitions using a fake audio source.

**Dependencies:** E1-S1, E1-S3  
**Estimate:** 8 points

---

## E1-S6 — Implement the recorder state machine and floating status overlay

**User story**

As a user, I want an unmistakable, non-disruptive indication of recording and
processing state so that I always know whether the microphone is active.

**Scope**

- State model: idle, preparing, recording, stopping, processing-placeholder, completed, cancelled, and failed.
- Floating, non-activating overlay that does not steal focus.
- Recording duration, input activity, stop, and cancel affordances.
- Reduced Motion and VoiceOver support.
- Optional start/stop sound that is off or configurable.

**Acceptance criteria**

- Given a valid shortcut activation, when preparation begins, then the overlay appears without changing the active text field.
- The overlay visually distinguishes preparing, recording, stopping, and failure states.
- Given Cancel is invoked, then recording ends, temporary audio is deleted, and focus remains with the target application.
- Given capture fails, then the overlay exits recording state and provides a useful next action.
- Given Reduce Motion is enabled, then essential state changes do not depend on animation.
- VoiceOver announces recording start, stop, cancel, and failure without reading live audio levels continuously.

**Dependencies:** E1-S4, E1-S5  
**Estimate:** 5 points

---

## E1-S7 — Add privacy-safe diagnostics and recoverable error reporting

**User story**

As a user and support engineer, I want useful diagnostics that exclude dictated
content so that problems can be resolved without exposing private information.

**Scope**

- Structured event categories for app lifecycle, permissions, shortcut registration, and audio state.
- Redaction policy that forbids audio, transcripts, cursor text, clipboard values, file contents, and user-entered vocabulary.
- User-visible diagnostics export with preview before sharing.
- Stable error identifiers and user-facing recovery guidance.

**Acceptance criteria**

- Logs record state transitions and error identifiers without recording sensitive payloads.
- A test containing canary secrets in fake audio metadata, field text, and clipboard content confirms none appear in diagnostics.
- Given an expected failure, then the UI maps it to a concise message and at least one valid recovery action.
- Given the user exports diagnostics, then the archive contents are previewable and contain app version, OS version, hardware class, permission states, and non-sensitive events.
- Diagnostics export is an explicit action and is never uploaded automatically.

**Dependencies:** E1-S1 through E1-S6  
**Estimate:** 3 points

---

## E1-S8 — Establish foundation CI and acceptance tests

**User story**

As a development team, we want automated checks for the foundation workflow so
that recording regressions are caught before they reach users.

**Scope**

- CI build and unit-test workflow.
- Static analysis/format validation selected by the team.
- State-machine tests and permission-model tests.
- UI smoke tests for menu-bar/settings entry and onboarding states where automation permits.
- Manual acceptance checklist for permission prompts and real microphone capture.

**Acceptance criteria**

- Every pull request builds the supported configuration and runs unit tests.
- The state machine has transition tests for all valid states and rejects invalid transitions.
- Permission presentation logic is tested for every permission state without changing the CI host settings.
- The repository contains a repeatable manual checklist for clean-install onboarding and real microphone verification.
- CI artifacts and logs do not include captured audio or other sensitive content.

**Dependencies:** E1-S1 through E1-S7  
**Estimate:** 5 points

## Epic 1 story order

1. E1-S1
2. E1-S2 and E1-S3
3. E1-S4 and E1-S5
4. E1-S6
5. E1-S7
6. E1-S8
