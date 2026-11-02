---
name: release-management
description: Version, changelog, archive, sign, notarize, and publish LemmeType macOS releases, and roll them back. Use when asked to cut a release, bump the version, prepare release notes, build a distributable/notarized app, tag a release, or plan a rollback.
---

# Release management

Distribution is direct download from GitHub Releases (Developer ID signed and
notarized), recorded in `docs/decisions/0026-distribution-and-updates.md`
(status *Proposed* until the product owner approves it). Confirm with the user
before any step that publishes, tags, or uploads anything.

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
5. **Privacy and performance gate** — complete `docs/security/privacy-release-checklist.md`
   (paste it into the release PR; `make privacy-docs-check` verifies it cites real
   checks). Verify Local mode is network-silent
   (`scripts/check-network-silence.sh --attach` plus Little Snitch or `nettop`
   during a dictation, MA-31), diagnostics contain no canary content, no new
   entitlements or TCC usage strings since the last release without
   justification. Run `make benchmark` on the minimum hardware; the threshold
   check (`docs/testing/performance-thresholds.json`) must pass and the
   thresholds must be *Approved* by a product owner.
6. **Archive, sign, notarize** — follow `docs/release/runbook.md`. In short
   (needs a Developer ID Application certificate and the team id in
   `Config/Signing.local.xcconfig`, which is gitignored; notary credentials live
   in your Keychain, never in the repo or chat):
   ```bash
   make release-build                                   # archive, export, zip, dmg, SHA256SUMS
   NOTARY_PROFILE=<profile> make release-notarize      # submit, staple, repackage, verify
   ```
   `make release-build REHEARSAL=1 && make release-verify REHEARSAL=1` rehearses
   the pipeline without a certificate; a rehearsal build is never shipped.
7. **Verify** — `scripts/verify-release.sh` (run by `release-notarize`) fails on a
   wrong version, missing Hardened Runtime, an entitlement outside
   `docs/security/entitlements-allowlist.txt`, `get-task-allow`, an unsigned
   embedded item, bundled recordings, or a missing stapled ticket. Then open the
   zip on a clean Mac (MA-59).
8. **Tag & publish** (after user confirmation): merge the release branch,
   `git tag -a vX.Y.Z -m "LemmeType X.Y.Z"`, push the tag, and
   `gh release create vX.Y.Z build/release/LemmeType-X.Y.Z.zip build/release/LemmeType-X.Y.Z.dmg build/release/SHA256SUMS --notes-file <notes>`
   (`--prerelease` for betas).
9. **Post-release** — merge the release branch back to `main`, close the
   milestone, and record known issues.

## Rollback

- Never delete a published tag or reuse a version number.
- Mark the bad GitHub release as pre-release/withdrawn and point the "latest"
  release back to the previous good build.
- Ship the fix as a new PATCH version with a higher build number.
- Follow `docs/release/rollback.md`. The in-app update check reads the GitHub
  release list, so marking a release as a pre-release or deleting it stops it
  being offered; copies users already installed stay until they update.

## Release notes

Write for users, not developers: what changed, what to do (e.g. re-grant a
permission), privacy-relevant changes called out explicitly, known issues.
