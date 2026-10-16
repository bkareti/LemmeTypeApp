# LemmeType

**Speak naturally. Write instantly.**

LemmeType is a privacy-first macOS voice-writing application. A user places the
cursor in any editable field, activates a global shortcut, speaks naturally,
and receives polished text at the cursor. Speech recognition, cleanup, and
context processing are local-first and designed to work without an account or
continuous internet connection.

## Product principles

- Local-first: audio and text stay on the user's Mac by default.
- Explicit: users can distinguish exact transcription from rewritten text.
- System-wide: the core workflow works across common macOS applications.
- Fast: starting, stopping, and inserting a short dictation should feel immediate.
- Respectful: sensitive context is never captured silently or retained by default.

## Repository status

This repository currently contains the product brief, roadmap, GitHub issue
templates, and development-ready scope for the first two epics. Application
source code will be introduced by Epic 1.

## Planning documents

- [Product brief](docs/product-brief.md)
- [Product roadmap and epics](docs/roadmap.md)
- [Epic 1 — macOS foundation and audio capture](docs/backlog/epic-01-macos-foundation.md)
- [Epic 2 — local dictation and text delivery](docs/backlog/epic-02-local-dictation.md)

## Initial delivery sequence

1. Prove global activation, audio recording, and a stable menu-bar lifecycle.
2. Prove local transcription and reliable insertion into the previously focused app.
3. Add context-aware writing and selected-text voice editing.
4. Add personalization, model management, privacy controls, and release hardening.

## License

No license has been selected yet. All rights are reserved until a license is
added explicitly.
