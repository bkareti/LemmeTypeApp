#!/usr/bin/env bash
# Notarizes and staples the built app, then repackages it (E7-S2, ADR 0026).
#
#   NOTARY_PROFILE=<keychain profile> scripts/notarize-release.sh [--dry-run]
#
# The profile is created once with `xcrun notarytool store-credentials`; the
# credentials stay in the maintainer's Keychain and are never read, printed, or
# stored here. Without NOTARY_PROFILE this stops with "NOT NOTARIZED" (exit 3)
# so a script can never report a build as notarized when it was not.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
dry=0
[[ "${1:-}" == "--dry-run" ]] && dry=1

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
  echo "NOT NOTARIZED: set NOTARY_PROFILE to a notarytool Keychain profile." >&2
  echo "  Create one once: xcrun notarytool store-credentials <name> --apple-id … --team-id … " >&2
  echo "  (see docs/release/runbook.md). Nothing was submitted." >&2
  exit 3
fi

out="$root/build/release"
app="$out/export/LemmeType.app"
version="$(sed -n 's/^MARKETING_VERSION[[:space:]]*=[[:space:]]*//p' "$root/Config/Version.xcconfig" | tr -d '[:space:]')"
submission="$out/notarize-LemmeType-$version.zip"

run() {
  if [[ $dry -eq 1 ]]; then echo "would run: $*"; else "$@"; fi
}

if [[ $dry -eq 0 ]]; then
  [[ -d "$app" ]] || { echo "error: $app not found; run make release-build first" >&2; exit 2; }
  [[ ! -e "$out/REHEARSAL" ]] || { echo "error: build/release is a REHEARSAL build; it cannot be notarized" >&2; exit 2; }
fi

run ditto -c -k --keepParent "$app" "$submission"
run xcrun notarytool submit "$submission" --keychain-profile "$NOTARY_PROFILE" --wait
run xcrun stapler staple "$app"
run xcrun stapler validate "$app"
run spctl --assess --type execute --verbose "$app"
run "$root/scripts/package-release.sh"
run "$root/scripts/verify-release.sh" "$app"
[[ $dry -eq 1 ]] && echo "Dry run: nothing was submitted." || echo "Notarized, stapled, repackaged, and verified."
