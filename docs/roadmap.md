# Product roadmap and epics

The roadmap is organized as GitHub epics. Epic 1 and Epic 2 are fully refined
and ready for development. Later epics remain outcome-level until the technical
prototype validates the core workflow.

## Epic 1 — macOS foundation, permissions, and audio capture

Build the native menu-bar foundation and prove that LemmeType can be activated
system-wide, obtain only the permissions it needs, and capture high-quality
microphone audio through an observable and recoverable recording lifecycle.

**Exit criteria**

- A signed development build launches as a menu-bar application.
- The user can complete microphone and Accessibility onboarding.
- A configurable global shortcut starts, stops, and cancels recording.
- Recording state is always visible and never continues silently.
- Captured audio is available to a downstream transcription service.
- Core behavior is covered by automated tests and privacy-safe diagnostics.

Detailed stories: [Epic 1 backlog](backlog/epic-01-macos-foundation.md)

## Epic 2 — local transcription, cleanup, and text delivery

Turn captured audio into useful text locally and deliver it reliably to the
text field that was active when dictation began.

**Exit criteria**

- Apple Speech and one downloadable local recognition engine are supported.
- Exact Dictation and deterministic Clean Writing modes are available.
- Text is inserted through Accessibility where supported.
- Clipboard fallback restores the user's previous clipboard content.
- The end-to-end workflow works offline on the supported application matrix.
- Latency, memory, failure, and privacy requirements are verified.

Detailed stories: [Epic 2 backlog](backlog/epic-02-local-dictation.md)

## Epic 3 — context-aware writing and voice editing

Use deliberately captured cursor context to match surrounding capitalization,
spacing, punctuation, and tone. Let users select text and speak an instruction
to rewrite, shorten, format, or translate it locally.

**Exit criteria**

- Cursor context is captured only during an explicit action.
- Password fields and configured sensitive apps are excluded.
- Context-aware formatting works without a language model.
- Selected-text editing works with a supported on-device language model.
- The user sees when context is used and can disable it globally or per app.

## Epic 4 — personalization, modes, vocabulary, and snippets

Let users configure LemmeType around their language, terminology, applications,
and recurring writing patterns.

**Exit criteria**

- Users can manage vocabulary, replacements, and reusable snippets.
- Modes can select transcription, cleanup, style, and output behavior.
- Modes can be activated manually or by application.
- Personalization data remains local and is exportable and deletable.

## Epic 5 — model management and performance

Make local models understandable, safe to download, and efficient across
supported Apple Silicon hardware.

**Exit criteria**

- Downloads show size, language support, and expected hardware requirements.
- Artifacts are verified before use and recover cleanly from interrupted downloads.
- Models load lazily and unload after a configurable idle period.
- Low-power and best-accuracy profiles are available.
- Memory pressure, thermal pressure, and insufficient storage are handled safely.

## Epic 6 — privacy, security, and data controls

Turn the local-first promise into verifiable product behavior rather than a
marketing claim.

**Exit criteria**

- Local mode is testably network-silent during dictation and cleanup.
- Audio and context retention defaults to off.
- History has explicit retention, export, and deletion controls.
- Sensitive data is excluded from analytics and diagnostics.
- Permission use and context collection are explained in plain language.
- A privacy threat model and release checklist are maintained.

## Epic 7 — quality, packaging, and release readiness

Prepare LemmeType for dependable installation and daily use across the supported
macOS and application matrix.

**Exit criteria**

- Automated unit, integration, UI, and compatibility suites pass.
- The app is signed, hardened, notarized, and updateable.
- Accessibility, localization readiness, crash recovery, and support diagnostics are verified.
- App Store versus direct distribution has a recorded decision and validated prototype.
- Beta feedback and release rollback processes are documented.

## Epic 8 — iPhone and iPad companion

Extend LemmeType to mobile without weakening the local-first promise. Begin with
Action Button, Back Tap, Shortcuts, and copy-to-clipboard dictation; evaluate an
optional custom keyboard after validating demand.

**Exit criteria**

- Quick Dictation records and processes locally in the main iOS app.
- Results can be copied and pasted with clear completion feedback.
- Shared product concepts such as modes, vocabulary, and cleanup reuse common code.
- Keyboard-extension tradeoffs are validated before requesting Full Access.

## Dependency order

Epic 1 → Epic 2 → Epic 3

Epic 2 also unlocks Epics 4 and 5. Epic 6 spans every epic. Epic 7 begins early
but completes after the MVP feature epics. Epic 8 starts after the macOS core is
validated.
