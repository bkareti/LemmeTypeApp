# Changelog

All notable changes to LemmeType are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/) (pre-1.0: a minor version for a
completed epic or user-visible feature set, a patch version for fixes). Story ids
(for example E6-S3) point to `docs/backlog/`.

## [Unreleased]

### Added

- Opt-in dictation history with a retention period, export, and deletion (E6-S3, E6-S4).
- Settings › Privacy: a plain-language overview of permissions and stored data, and
  Delete All Local Data (E6-S5).
- Check for Updates in Settings › General and the menu; an optional weekly check, off by
  default. It sends only the app version and never downloads or installs anything (E7-S3).
- A notice in the menu after LemmeType closed unexpectedly (E7-S4).
- About and support: Copy Support Info and Report a Problem (E7-S5); a richer, still
  content-free diagnostics report (E7-S5).
- A complete string catalog with translator comments, ready for translation (E7-S7).

### Changed

- The Permissions pane and onboarding use the shared plain-language permission text (E6-S5).
- Diagnostics reports have schema version 2 (E7-S5).

### Security

- CI now fails on network code outside an allowlist, on a new entitlement, permission
  string, or dependency, and on a stale privacy threat model (E6-S2, E6-S7, E6-S8).
- The release pipeline verifies Hardened Runtime, entitlements, version, and contents of
  every build (E7-S2).

### Fixed

- Speech recognition now hears the whole recording. The last 8–64 ms of every dictation
  was dropped before it reached Whisper or Apple Speech.

## [0.1.0] - not released

The development build described by Epics 1 to 5, 9, and 10: menu-bar app, local
transcription, Exact and Clean writing, cursor context and voice editing,
personalization and modes, model management, multilingual dictation and
speech-to-English, and tone and style rewriting.
