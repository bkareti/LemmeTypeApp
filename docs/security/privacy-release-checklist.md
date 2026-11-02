# Privacy release checklist

Run for every release candidate and every beta, with the build that will ship.
Each item names how to check it. `scripts/check-privacy-docs.py` verifies that
those checks exist. Paste the completed list into the release pull request.

Release: ____  Build: ____  Mac / macOS: ____  Checked by: ____  Date: ____

## Automated (must be green on the release commit)

- [ ] Network APIs are only in allowlisted files. — `make network-check`
- [ ] No internet socket opens during full sessions. — `NetworkSilenceTests`
- [ ] Entitlements, permission strings, and dependencies match the allowlists, and Hardened Runtime is on. — `make security-check`
- [ ] No canary text in diagnostics, reports, or error identifiers. — `DiagnosticsCanaryTests`
- [ ] The report schema has not changed without review. — `DiagnosticsReportSchemaTests`
- [ ] History is off by default and writes nothing when off. — `PrivacyEndToEndTests`
- [ ] Delete All Local Data leaves nothing behind. — `PrivacyOverviewModelTests`
- [ ] No captured audio is left behind by the tests. — `make privacy-check`
- [ ] The threat model and this checklist still match the code. — `make privacy-docs-check`

## Release artifact

- [ ] The built app has no recordings, transcripts, or benchmark output. — `scripts/check-release-artifact.sh`
- [ ] The built app's entitlements are only the allowlisted ones. — `scripts/check-security-config.py`
- [ ] The third-party notices list every dependency. — `THIRD_PARTY_NOTICES.md`
- [ ] Hardened Runtime, entitlements, signature, version, and contents are verified, and the build is notarized and stapled. — `scripts/verify-release.sh`

## On a real Mac

- [ ] No network connection during dictation, cleanup, translation, rewriting, or history use. — `MA-54`
- [ ] History is off on a clean install, and every control works. — `MA-55`
- [ ] Delete All Local Data removes what it says. — `MA-56`
- [ ] A person outside the team understood the Privacy pane. — `MA-57`
- [ ] Files are owner-only, and unreadable data is set aside. — `MA-58`
- [ ] Insertion never targets a password field. — `MA-33`
- [ ] The update check sends only the version, and only when asked. — `MA-60`
- [ ] A killed app starts cleanly and tells the user once. — `MA-62`

## Release notes

- [ ] Any change to what is stored, sent, or asked of the user is stated plainly in the release notes. — `docs/security/threat-model.md`
- [ ] New permissions, entitlements, or network use have an ADR and a threat-model row. — `docs/decisions/0025-privacy-data-and-history.md`
