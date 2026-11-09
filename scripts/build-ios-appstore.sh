#!/usr/bin/env bash
# Archives the iPhone and iPad app for the App Store (docs/release/app-store.md) and
# checks the archive for what App Store processing and App Review reject
# (scripts/verify-ios-appstore.sh). With a team id it exports a signed .ipa, or
# uploads it to App Store Connect with --upload. Without one (--check) it archives
# unsigned: good for the checks, not for uploading.
#
#   scripts/build-ios-appstore.sh [--check | --upload]
#
# Environment (never put these in the repository):
#   TEAM_ID  Apple team id (else DEVELOPMENT_TEAM in Config/Signing.local.xcconfig)
# Uploading uses the Apple ID signed in to Xcode (Settings › Accounts).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="$root/build/ios-appstore"
mode="export"
case "${1:-}" in
  --check) mode="check" ;;
  --upload) mode="upload" ;;
  "") ;;
  *) echo "usage: $0 [--check | --upload]" >&2; exit 2 ;;
esac

team="${TEAM_ID:-}"
if [[ -z "$team" && -f Config/Signing.local.xcconfig ]]; then
  team="$(sed -n 's/^DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' Config/Signing.local.xcconfig | tr -d '[:space:]' | head -n 1)"
fi
if [[ $mode != check && ( -z "$team" || "$team" == "YOURTEAMID" ) ]]; then
  echo "error: no Apple team id. Join the Apple Developer Program, then set TEAM_ID" >&2
  echo "       (or DEVELOPMENT_TEAM in Config/Signing.local.xcconfig). Use --check to archive unsigned." >&2
  exit 2
fi

rm -rf "$out"
mkdir -p "$out"
xcodegen generate --quiet

archive=(xcodebuild archive -project LemmeType.xcodeproj -scheme LemmeTypeiOS -configuration Release
  -destination 'generic/platform=iOS' -archivePath "$out/LemmeType.xcarchive" -derivedDataPath "$out/DerivedData")
if [[ $mode == check ]]; then
  archive+=(CODE_SIGNING_ALLOWED=NO)
else
  archive+=(CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=$team" -allowProvisioningUpdates)
fi
"${archive[@]}" > "$out/archive.log" 2>&1 || { tail -n 30 "$out/archive.log" >&2; echo "error: archive failed (see $out/archive.log)" >&2; exit 1; }

scripts/verify-ios-appstore.sh "$out/LemmeType.xcarchive" "$out/archive.log"

if [[ $mode == check ]]; then
  echo "Unsigned archive checked. To upload: TEAM_ID=<team> scripts/build-ios-appstore.sh --upload"
  exit 0
fi
options="$(mktemp)"
trap 'rm -f "$options"' EXIT
destination="export"
[[ $mode == upload ]] && destination="upload"
sed -e "s/__TEAM_ID__/$team/" -e "s/__DESTINATION__/$destination/" Config/ExportOptions-AppStore.plist > "$options"
xcodebuild -exportArchive -archivePath "$out/LemmeType.xcarchive" -exportOptionsPlist "$options" \
  -exportPath "$out/export" -allowProvisioningUpdates > "$out/export.log" 2>&1 \
  || { tail -n 30 "$out/export.log" >&2; echo "error: export failed (see $out/export.log)" >&2; exit 1; }
if [[ $mode == upload ]]; then
  echo "Uploaded to App Store Connect. It appears under TestFlight after processing."
else
  echo "Exported: $out/export (upload it with Xcode's Organizer or Transporter)"
fi
