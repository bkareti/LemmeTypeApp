# 0004 — Permission model and onboarding

- Status: Accepted
- Date: 2026-10-16
- Story: E1-S3

## Decision

- **Statuses only claim what macOS reports.** Microphone uses
  `notRequested / granted / denied / restricted` from `AVCaptureDevice`.
  Accessibility uses only `granted / notGranted`, because `AXIsProcessTrusted`
  cannot tell "never asked" from "denied" and has no restricted state.
- **Explain, then ask.** Onboarding has one screen per permission; the system
  prompt appears only when the user presses the request button on that screen.
- **No re-prompting.** Microphone is requested only while `notRequested`;
  afterwards the only action is opening System Settings. Accessibility is
  requested once per session (`AXIsProcessTrustedWithOptions` with the prompt
  option, which also adds LemmeType to the Accessibility list); later the
  action is "Open System Settings…".
- **Live state.** A single `PermissionsModel` is shared by onboarding, the
  Permissions pane, and the status menu. It refreshes on app activation and
  polls every second while a permission screen is visible, because
  Accessibility has no change notification.
- **Limited mode.** Setup can finish without permissions. Capabilities map to
  permissions (`recording` → Microphone, `textInsertion` → Accessibility) and
  are shown as Available/Unavailable; the menu offers "Finish Setup…" until
  everything is granted.
- **Persistence.** `AppPreferences.hasCompletedOnboarding` (UserDefaults)
  decides whether onboarding opens at launch. `Support` now depends on
  `Domain` so it can implement this protocol.

## Consequences

- Screen Recording and Input Monitoring are not modelled; adding either needs a
  new ADR and story justification.
- Ad-hoc–signed Debug builds lose Accessibility trust on every rebuild; use
  team signing (`Config/Signing.local.xcconfig`) when checking MA-6 to MA-8.
