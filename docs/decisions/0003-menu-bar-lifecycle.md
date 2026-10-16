# 0003 — Menu-bar lifecycle, settings window, and single instance

- Status: Accepted
- Date: 2026-10-16
- Story: E1-S2

## Decision

- **Agent app**: `LSUIElement = YES` — no Dock icon or main window. The
  SwiftUI `MenuBarExtra` (menu style) is the app's only scene.
- **Settings window** is an AppKit `NSWindow` hosting SwiftUI, owned by
  `SettingsWindowController` (UI module). It is created on first use, kept
  (`isReleasedWhenClosed = false`), and re-fronted on every request, which
  guarantees exactly one window. The SwiftUI `Settings` scene was rejected
  because an agent app cannot open it reliably from AppKit code (single-instance
  hand-off, Dock reopen) — only from a SwiftUI view through `openSettings`.
- **Launch at Login** uses `SMAppService.mainApp`. The UI always shows the
  status macOS reports (`enabled`, `notRegistered`, `requiresApproval`,
  `notFound`) rather than a stored preference.
- **Single instance**: on launch, the earliest-launched running copy with the
  same bundle identifier wins (`InstancePolicy`). A later copy posts a local
  `DistributedNotificationCenter` notification asking the winner to show
  Settings, then terminates before creating any recorder or shortcut state.
- **New module `Lifecycle`** (depends on Domain + Support) holds the
  ServiceManagement and NSRunningApplication integrations.

## Consequences

- XCUITest cannot click items in a status-bar menu (it re-activates the app,
  which dismisses the menu). UI tests check menu contents and states; menu
  actions are covered by hosted `AppControllerTests` and manual check MA-3. The
  Debug-only `-LemmeTypeShowSettings` launch argument opens Settings for UI tests.
- `SMAppService` registration of a Debug build in DerivedData may report
  `requiresApproval` or fail; verify Launch at Login with a build in
  /Applications (MA-5).
- Distributed notifications stay on the local machine and carry no payload.
