# 0026 — Distribution channel and update mechanism

- Status: Proposed (needs product-owner approval; the App Sandbox experiment has not been run)
- Date: 2026-11-01
- Stories: E7-S1 … E7-S3 (issues #108–#110, epic #7)

## Context

Epic 7 must make LemmeType installable, updateable, and withdrawable. Two
questions are open: **where users get the app** (direct download or the Mac App
Store) and **how they get a new version**. ADR 0001 assumed Developer ID and
notarization and left the final decision to this epic. ADR 0025 forbids network
code outside a short allowlist and forbids analytics.

## Decision

### Channel: Developer ID, direct download

| | Direct download (Developer ID, notarized) | Mac App Store |
|---|---|---|
| App Sandbox | Off (ADR 0001) | Required |
| Cross-app Accessibility (read the focused field, insert text) | Works with the Accessibility permission | **Not proven** under the sandbox. This ADR does not rely on it; see "Evidence missing" |
| Model downloads | Allowed; one allowlisted host | Needs the sandbox network entitlement; allowed |
| Time to ship a fix | Minutes (publish a release) | Review time |
| Review risk | None beyond notarization | An app that drives other apps through Accessibility can be questioned |
| Updates | Our own (below) | The Store |
| Trust signal | Notarized by Apple, Gatekeeper opens it | Store badge |
| Cost to prototype | Done here: `scripts/build-release.sh` | Needs an entitlement and sandbox rework |

**Chosen:** direct download from GitHub Releases, signed with a Developer ID
Application certificate, hardened, notarized, and stapled, as a zip and a disk
image with published SHA-256 checksums. The Mac App Store is not pursued now.

### Evidence

- **Validated by the prototype (E7-S2):** an archive builds with Hardened
  Runtime; the signature, entitlements, version, architecture, and artifact
  contents are verified by `scripts/verify-release.sh`; the same script run on a
  real Developer ID build and `spctl`/`stapler` cover Gatekeeper. A rehearsal
  build (ad-hoc signed) was verified on the development Mac. A real Developer ID
  build and notarization still need the maintainer's certificate and notary
  profile: **not verified here.**
- **Evidence missing for the Store path:** build with `com.apple.security.app-sandbox`
  and try the Accessibility insertion path into TextEdit and Notes (MA-61). If it
  works, revisit; if not, record the result here and mark the Store path closed.

### Updates: a check the user starts, a download the browser performs

| | User-started check + manual download | Third-party updater (for example Sparkle) | None |
|---|---|---|---|
| New dependency | None | Yes (licence, maintenance, key custody) | None |
| Network code in the app | One small file (ADR 0025 allowlist) | The updater's own | None |
| What the app downloads | Version metadata only | Application code, then runs it | Nothing |
| Update-channel attack surface | A spoofed "new version" message that links to a GitHub page | A malicious or downgraded update would be executed | None |
| User effort | Click, download, replace the app | Click or automatic | Find it yourself |
| Signing keys to protect | Developer ID (already needed) | Developer ID and an update-signing key | Developer ID |

**Chosen:** the `Updates` module makes one HTTPS request when the user asks (or
weekly, if they turn it on) and tells them a newer version exists. **The app
never downloads or runs code.** The user opens the release page in their browser,
where Gatekeeper and notarization protect the download, and the page shows the
SHA-256 checksum. Revisit a seamless updater before 1.0 if the manual flow costs
users; it would need its own ADR and an update-signing key plan.

### The check

- One `GET https://api.github.com/repos/bkareti/LemmeTypeApp/releases?per_page=10`,
  an ephemeral session (no cookies, cache, credentials, or redirects off GitHub), a
  15-second timeout, a 1 MB response limit, and headers limited to `Accept`,
  `User-Agent: LemmeType/<version>`, and `X-GitHub-Api-Version`. No identifier,
  no installed-model list, no system profile.
- Draft releases are ignored. Pre-releases are ignored unless the running build is
  a pre-release. A release is offered only if its version is **higher** than the
  running one (no downgrade offer).
- The page link must be `https://github.com/bkareti/LemmeTypeApp/releases/…`;
  anything else is rejected.
- No check while a dictation session is active, and none unless the user asked or
  turned on "Check weekly" (off by default).
- A 404 or an empty list means "no release published yet"; offline means
  "couldn't check". Neither is an error screen.
- The Privacy pane says what is sent: the app version and, as with any web
  request, the IP address, to GitHub.
- The file is added to `docs/security/network-allowlist.txt` and gets the
  SwiftLint `no_network_apis` exception, in that file only.

### New module

`Updates` (depends on Domain and Support). It contains `GitHubReleaseFeed`
(the only file with `URLSession`) and `UpdateChecker` (policy, schedule, state).
Domain holds `SemanticVersion`, `ReleaseInfo`, `UpdateChecking`, and
`UpdateStatus`. The edge is `Updates → Domain, Support`; the UI depends on the
Domain protocol only.

### Distribution channel in diagnostics

`DiagnosticsReport` gets a `distributionChannel` of `direct` (Release build) or
`development` (Debug).

## Consequences

- The release pipeline (`docs/release/runbook.md`) and the rollback process
  (`docs/release/rollback.md`) are built for GitHub Releases.
- Withdrawing a release (mark it a pre-release or delete it) removes it from what
  the check offers. It does not remove copies users already installed.
- Users update by replacing the app; settings, history, and personalization stay
  in place and are never overwritten by an older version (ADR 0020, ADR 0025).
- There is no automatic update. A user who never checks stays on their version.

## Open questions (proposed defaults)

1. Should the first public beta use a pre-release tag (`v0.2.0-beta.1`)? Yes.
2. Should "Check weekly" be offered at first run? No: off, discoverable in
   Settings › General › Updates.
3. Should the app show release notes? The release page does; the app shows the
   version and a link only, so no remote text is rendered inside the app.
