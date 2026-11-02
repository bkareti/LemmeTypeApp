# Rolling back a release

When a published build turns out to be bad, this is the process. The aim is to stop new
people getting it, give existing users a safe way back, and ship a fixed build, without
rewriting history. Distribution is described in [ADR 0026](../decisions/0026-distribution-and-updates.md).

## When to roll back

Withdraw a release if any of these is true, and decide within a day of the report:

- Dictation does not work for a large share of users, or text is typed into the wrong place.
- Data is lost or an older version cannot read what this version wrote.
- A privacy promise is broken (something is stored or sent that should not be), or a
  security hole is found.
- The build is not correctly signed or notarized.

Otherwise ship a fix as the next patch release.

## Rules

- **Never delete a published tag, and never reuse a version number.** Users and
  checksums refer to them.
- **A newer version is the fix.** Roll forward with a higher patch version and a higher
  build number whenever you can.
- Data files are never overwritten by an older version: an unreadable or newer file is
  moved aside, not replaced (ADR 0020, ADR 0025). Going back loses no history or vocabulary.

## Steps

All commands use the GitHub CLI and need the maintainer's confirmation each time.

1. **Say what is wrong.** Open an issue labelled `beta-feedback` or `release-blocker` that
   names the version and the symptom. Link it from the release.
2. **Stop new downloads and update offers.** The in-app update check reads the release
   list and ignores drafts, and ignores pre-releases unless the user is on one. To
   withdraw release `vX.Y.Z`:
   ```bash
   gh release edit vX.Y.Z --prerelease            # no longer offered to stable users
   # or, to hide it completely:
   gh release edit vX.Y.Z --draft
   ```
   Add a line at the top of the release notes: *"Withdrawn: <reason>. Use vA.B.C."*
   (`gh release edit vX.Y.Z --notes-file <file>`).
3. **Point people at the last good build.** If the previous release was marked as a
   pre-release or draft, restore it to a normal release:
   ```bash
   gh release edit vA.B.C --prerelease=false --latest
   ```
4. **Tell users.** Post in the issue and the release notes what to do: replace the app with
   `vA.B.C` (download from its release page, quit LemmeType, replace, open). Settings,
   vocabulary, and history stay.
5. **Fix forward.** Branch `release/X.Y.(Z+1)` from the last good commit, fix, bump
   `Config/Version.xcconfig` (new build number), update `CHANGELOG.md`, and follow the
   [runbook](runbook.md). Mention the withdrawn build in the release notes.
6. **After.** Record what happened and what check would have caught it (a test, a
   checklist line, a step in `manual-acceptance.md`) in the release pull request.

## What a withdrawal does not do

- It does not uninstall or disable copies people already have. There is no remote switch,
  by design (the app downloads and runs nothing).
- It does not stop someone who kept the old zip. The checksum on the release page tells
  them which build they have.

## Rehearsal

Before the first public release, walk through steps 2 and 3 on a **draft** release
(drafts are invisible to users): create `v0.0.0-rollback-rehearsal` as a draft, edit it to
pre-release, edit it back, delete the draft. Record what each command printed in the pull
request. Nothing is published.
