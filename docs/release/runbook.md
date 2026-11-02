# Release runbook

How a LemmeType build becomes a notarized download. Direct distribution through
GitHub Releases ([ADR 0026](../decisions/0026-distribution-and-updates.md)).
Publishing, tagging, and uploading need the maintainer's confirmation each time.

## One-time setup (the maintainer's Mac)

1. Install a **Developer ID Application** certificate in your login Keychain
   (Xcode › Settings › Accounts › Manage Certificates, or developer.apple.com).
2. Put your team id in `Config/Signing.local.xcconfig` (gitignored):
   `DEVELOPMENT_TEAM = ABCDE12345`, or export `TEAM_ID` for one run.
3. Store notarization credentials once. They stay in your Keychain; nothing goes
   in the repository, the shell history of a shared machine, or chat:
   ```bash
   xcrun notarytool store-credentials lemmetype-notary --apple-id <you@example.com> --team-id <TEAMID>
   ```
   It asks for an app-specific password. `lemmetype-notary` is the profile name
   used below.

## Rehearse (any Mac, no certificate)

```bash
make release-script-tests            # fixture tests for the scripts
make release-build REHEARSAL=1       # ad-hoc archive → build/release
make release-verify REHEARSAL=1      # signature, Hardened Runtime, entitlements, version, contents
```

Expected: `Release artifact verified (rehearsal: not notarized).` A rehearsal
build is marked by `build/release/REHEARSAL`, is refused by `release-notarize`,
and must never be shipped. CI runs this on every change (`release-readiness`).

## Release

1. **Scope and version** — follow `.claude/skills/release-management/SKILL.md`:
   branch `release/X.Y.Z`, bump `Config/Version.xcconfig`, update `CHANGELOG.md`.
2. **Gates** — `make quality-gate` is green; `docs/security/privacy-release-checklist.md`
   is complete; `docs/testing/manual-acceptance.md` is run on a clean account.
3. **Build** — signs with your Developer ID identity and exports:
   ```bash
   make release-build
   ```
   Expected: `Signed with: Developer ID Application: …`, then the zip, disk image,
   and `SHA256SUMS` in `build/release/`.
4. **Verify the signed build**
   ```bash
   scripts/verify-release.sh build/release/export/LemmeType.app --rehearsal
   ```
   (`--rehearsal` only skips the Gatekeeper and ticket checks, which come next.)
5. **Notarize and staple**
   ```bash
   NOTARY_PROFILE=lemmetype-notary make release-notarize
   ```
   It submits, waits for Apple, staples the ticket, runs `spctl`, re-packages the
   *stapled* app, and runs the full verification (without `--rehearsal`).
   Expected last line: `Notarized, stapled, repackaged, and verified.`
   Without `NOTARY_PROFILE` it prints `NOT NOTARIZED` and exits 3; nothing is
   submitted. `scripts/notarize-release.sh --dry-run` lists the steps.
6. **Clean-Mac check** — copy the zip to a Mac that has never run LemmeType,
   download it the way a user would (Safari or `curl -O` keeps the quarantine
   flag), unzip, move to Applications, open it: no Gatekeeper warning beyond the
   first-open confirmation, and the onboarding appears (MA-59).
7. **Publish** (after the maintainer confirms): merge the release branch,
   `git tag -a vX.Y.Z -m "LemmeType X.Y.Z"`, push the tag, then
   ```bash
   gh release create vX.Y.Z build/release/LemmeType-X.Y.Z.zip build/release/LemmeType-X.Y.Z.dmg \
     build/release/SHA256SUMS --title "LemmeType X.Y.Z" --notes-file <notes> [--prerelease]
   ```
   Use `--prerelease` for betas (`vX.Y.Z-beta.N`). The app's update check ignores
   pre-releases unless the user is on one.
8. **After** — merge the release branch back, record known issues, and watch the
   beta feedback labels ([beta program](beta-program.md)). To withdraw a build see
   the [rollback process](rollback.md).

## What each script checks

| Script | Fails when |
|---|---|
| `scripts/verify-release.sh` | The bundle id, version, build, minimum macOS, or usage strings are wrong; it is not arm64 only; the signature (deep, strict) is invalid or any embedded item is unsigned; Hardened Runtime is off; entitlements differ from `docs/security/entitlements-allowlist.txt` or include `get-task-allow`; recordings, transcripts, or benchmark output are inside; Gatekeeper rejects it or no ticket is stapled (not in rehearsal) |
| `scripts/notarize-release.sh` | `NOTARY_PROFILE` is unset (exit 3), the build is a rehearsal, or Apple rejects the submission |
| `scripts/check-release-artifact.sh` | A recording, transcript, benchmark file, or test bundle is inside the app, zip, or image |

## Not verified in this repository's CI

A real Developer ID signature, notarization, stapling, and Gatekeeper on a clean
Mac need the maintainer's certificate and notary profile. The first real run is
recorded in the release pull request (MA-59).
