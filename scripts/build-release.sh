#!/usr/bin/env bash
# Builds the release artifact (E7-S2, ADR 0026): archive the Release
# configuration, export it with a Developer ID identity, then zip, image, and
# checksum it. Without a Developer ID identity, or with --rehearsal, it builds
# the same archive signed ad hoc and labels the result REHEARSAL: good for
# checking the pipeline and Hardened Runtime, not for shipping.
#
#   scripts/build-release.sh [--rehearsal]
#
# Environment (never put these in the repository):
#   DEVELOPER_ID_IDENTITY  override the signing identity name
#   TEAM_ID                Apple team id (else DEVELOPMENT_TEAM in Config/Signing.local.xcconfig)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="$root/build/release"
rehearsal=0
[[ "${1:-}" == "--rehearsal" ]] && rehearsal=1

team="${TEAM_ID:-}"
if [[ -z "$team" && -f Config/Signing.local.xcconfig ]]; then
  team="$(sed -n 's/^DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' Config/Signing.local.xcconfig | tr -d '[:space:]' | head -n 1)"
fi
identity="${DEVELOPER_ID_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
fi

if [[ $rehearsal -eq 0 && ( -z "$identity" || -z "$team" || "$team" == "YOURTEAMID" ) ]]; then
  echo "error: no Developer ID Application identity and team id were found." >&2
  echo "       Install the certificate and set TEAM_ID (or DEVELOPMENT_TEAM in Config/Signing.local.xcconfig)," >&2
  echo "       or run with --rehearsal for an ad-hoc build that only checks the pipeline." >&2
  exit 2
fi

rm -rf "$out"
mkdir -p "$out"
xcodegen generate --quiet

archive=(xcodebuild archive -project LemmeType.xcodeproj -scheme LemmeType -configuration Release
  -destination 'generic/platform=macOS' -archivePath "$out/LemmeType.xcarchive"
  -derivedDataPath "$out/DerivedData" ARCHS=arm64)
if [[ $rehearsal -eq 0 ]]; then
  archive+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" "DEVELOPMENT_TEAM=$team" OTHER_CODE_SIGN_FLAGS=--timestamp)
fi
"${archive[@]}" > "$out/archive.log" 2>&1 || { tail -n 30 "$out/archive.log" >&2; echo "error: archive failed (see $out/archive.log)" >&2; exit 1; }

mkdir -p "$out/export"
if [[ $rehearsal -eq 0 ]]; then
  options="$(mktemp)"
  trap 'rm -f "$options"' EXIT
  sed "s/__TEAM_ID__/$team/" Config/ExportOptions-DeveloperID.plist > "$options"
  xcodebuild -exportArchive -archivePath "$out/LemmeType.xcarchive" -exportOptionsPlist "$options" \
    -exportPath "$out/export" > "$out/export.log" 2>&1 || { tail -n 30 "$out/export.log" >&2; echo "error: export failed" >&2; exit 1; }
else
  ditto "$out/LemmeType.xcarchive/Products/Applications/LemmeType.app" "$out/export/LemmeType.app"
  : > "$out/REHEARSAL"
fi

scripts/package-release.sh
if [[ $rehearsal -eq 1 ]]; then
  echo "REHEARSAL build (ad-hoc signed). It is not notarized and must not be shipped."
else
  echo "Signed with: $identity"
  echo "Next: make release-verify, then make release-notarize"
fi
