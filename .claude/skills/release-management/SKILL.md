---
name: release-management
description: Version, changelog, archive, sign, notarize, and publish LemmeType macOS releases, and roll them back. Use when asked to cut a release, bump the version, prepare release notes, build a distributable/notarized app, tag a release, or plan a rollback.
---

# Release management

Distribution channel (direct download vs Mac App Store) is still an open
Epic 7 decision. Until an ADR records it, releases are **internal builds**:
Developer ID–signed, notarized, distributed as a zip/DMG through GitHub
Releases on `bkareti/LemmeTypeApp`. Confirm with the user before any step that
publishes, tags, or uploads anything.

## Versioning

- `MARKETING_VERSION` (SemVer `MAJOR.MINOR.PATCH`) and
  `CURRENT_PROJECT_VERSION` (monotonic integer build number) live in
  `Config/Version.xcconfig`. Never set them anywhere else.
- Pre-1.0: MINOR for a completed epic or user-visible feature set, PATCH for
  fixes. Pre-releases are tagged `vX.Y.Z-beta.N`.
- Every build that leaves a developer's machine gets a new build number.

## Release checklist

1. **Scope** — list merged PRs since the last tag:
   `git log --oneline <last-tag>..main` and `gh pr list --state merged`.
   Confirm with the user which stories/epic exit criteria the release covers.
2. **Branch** — `release/X.Y.Z` from `main`. Only fixes land on it.
3. **Version** — bump `Config/Version.xcconfig`; update `CHANGELOG.md`
   (Keep a Changelog format: Added / Changed / Fixed / Security, story IDs in
   each line).
4. **Quality gate** — `make lint`, `make test`, CI green, and every step in
   `docs/testing/manual-acceptance.md` executed on a clean user account, with
   results recorded in the PR.
5. **Privacy and performance gate** — verify Local mode is network-silent
   (`scripts/check-network-silence.sh --attach` plus Little Snitch or `nettop`
   during a dictation, MA-31), diagnostics contain no canary content, no new
   entitlements or TCC usage strings since the last release without
   justification. Run `make benchmark` on the minimum hardware; the threshold
   check (`docs/testing/performance-thresholds.json`) must pass and the
   thresholds must be *Approved* by a product owner.
6. **Archive & sign** (requires a Developer ID Application certificate and the
   team ID in `Config/Signing.local.xcconfig`, which is gitignored):
   ```bash
   xcodebuild archive -project LemmeType.xcodeproj -scheme LemmeType \
     -configuration Release -archivePath build/LemmeType.xcarchive
   xcodebuild -exportArchive -archivePath build/LemmeType.xcarchive \
     -exportOptionsPlist Config/ExportOptions-DeveloperID.plist -exportPath build/export
   ```
   Hardened Runtime must be on for Release.
7. **Notarize & staple** (credentials stored once with
   `xcrun notarytool store-credentials`; never put them in the repo or chat):
   ```bash
   ditto -c -k --keepParent build/export/LemmeType.app build/LemmeType.zip
   xcrun notarytool submit build/LemmeType.zip --keychain-profile <profile> --wait
   xcrun stapler staple build/export/LemmeType.app
   spctl --assess --type execute --verbose build/export/LemmeType.app
   scripts/check-release-artifact.sh build/LemmeType.zip
   ```
   The artifact check fails if the app contains recordings, transcripts, or
   benchmark output.
8. **Tag & publish** (after user confirmation): merge the release branch,
   `git tag -a vX.Y.Z -m "LemmeType X.Y.Z"`, push the tag, and
   `gh release create vX.Y.Z build/LemmeType-X.Y.Z.zip --notes-file <notes>`
   (`--prerelease` for betas). Attach SHA-256 checksums.
9. **Post-release** — merge the release branch back to `main`, close the
   milestone, and record known issues.

## Rollback

- Never delete a published tag or reuse a version number.
- Mark the bad GitHub release as pre-release/withdrawn and point the "latest"
  release back to the previous good build.
- Ship the fix as a new PATCH version with a higher build number.
- Once an updater exists (Epic 7), document how to stop the update feed here.

## Release notes

Write for users, not developers: what changed, what to do (e.g. re-grant a
permission), privacy-relevant changes called out explicitly, known issues.
