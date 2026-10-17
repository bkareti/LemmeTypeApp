# 0016 — Engine and writing-mode selection

- Status: Accepted
- Date: 2026-10-17
- Story: E2-S9

## Decision

- **One model for Settings and the menu** — `DictationSettingsModel` (UI)
  shows every engine with readiness, processing location (always *On this
  Mac*), supported languages, and what must be installed (nothing, macOS
  dictation languages, or a sized download). It owns model download, pause,
  resume, removal, and unloading, and the clipboard-fallback setting. It
  refreshes engine availability when Settings or the app becomes active, at
  launch, and after every session.
- **Settings › Dictation** pane (new `SettingsNavigation.Pane.dictation`;
  *Choose Engine…* in the overlay opens it). Exact and Clean are radio options
  whose plain-language descriptions are always visible, so the behaviour is
  read before choosing.
- **Status menu** — a *Writing Mode:* submenu to switch modes and a line such as
  *Engine: Automatic (Apple Speech) · On this Mac*; when nothing can run it
  becomes *No On-Device Engine Ready — Set Up…*.
- **Automatic** picks the first ready engine in recommendation order
  (Apple Speech, then Whisper) that supports the language, and the pane says
  which one and why. Only local engines exist (`ProcessingLocation.onDevice`);
  there is no cloud fallback to hide.
- **Snapshot per session** — `RecordingCoordinator` reads mode, language, and
  `EnginePreference` (selected engine + automatic-fallback flag) when
  recording *starts* and stores them in the `DictationSession`. The pipeline
  no longer reads preferences, so changing the engine mid-recording or
  mid-processing only affects the next session.
- **Unavailable chosen engine** — never swapped silently: the pane shows a
  blocked notice with the fix, and the session asks (needs-attention with
  *Use <ready engine>*). The only exception is the user's explicit, previously
  approved policy *If my engine isn't ready, use another on-device engine
  without asking* (`fallsBackToReadyEngine`, off by default), which
  `EngineSelector` applies.
- **Removing a model** unloads its engine and keeps the selection; the next
  session asks (or follows the approved policy).

## Consequences

- MA-22/MA-23/MA-24 (model download, removal, unload) now have their UI.
- The language list is the union of engine languages; an engine that doesn't
  support the chosen language is shown as such and Automatic skips it.
