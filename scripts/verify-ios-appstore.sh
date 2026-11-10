#!/usr/bin/env bash
# Checks an iPhone and iPad App Store archive for what App Store processing or App
# Review rejects (docs/release/app-store.md). Prints one line per check; exits 1 on
# any failure.
#
#   scripts/verify-ios-appstore.sh <LemmeType.xcarchive> [archive.log]
set -uo pipefail

archive="${1:?usage: $0 <LemmeType.xcarchive> [archive.log]}"
log="${2:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"
app="$archive/Products/Applications/LemmeType.app"
plist="$app/Info.plist"
failures=0
ok() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
check() { if eval "$2"; then ok "$1"; else fail "$1"; fi; }
value() { plutil -extract "$1" raw -o - "$plist" 2>/dev/null; }

[[ -d "$app" ]] || { echo "error: no app in $archive" >&2; exit 1; }
version="$(sed -n 's/^MARKETING_VERSION = //p' "$root/Config/Version.xcconfig")"

check "bundle id com.lemmetype.LemmeType.iOS" '[[ "$(value CFBundleIdentifier)" == com.lemmetype.LemmeType.iOS ]]'
check "version $version" '[[ "$(value CFBundleShortVersionString)" == "$version" ]]'
check "build number is an integer" '[[ "$(value CFBundleVersion)" =~ ^[0-9]+$ ]]'
check "microphone usage string" '[[ -n "$(value NSMicrophoneUsageDescription)" ]]'
check "speech recognition usage string" '[[ -n "$(value NSSpeechRecognitionUsageDescription)" ]]'
check "export compliance: no non-exempt encryption" '[[ "$(value ITSAppUsesNonExemptEncryption)" == false ]]'
check "only the audio background mode (Action Button dictation, ADR 0032)" '[[ "$(plutil -extract UIBackgroundModes json -o - "$plist")" == "[\"audio\"]" ]]'
check "launch screen" 'plutil -extract UILaunchScreen xml1 -o - "$plist" >/dev/null 2>&1'
check "iPhone and iPad" '[[ "$(plutil -extract UIDeviceFamily json -o - "$plist")" == "[1,2]" ]]'
check "app icon compiled" '[[ -f "$app/Assets.car" ]] && [[ -n "$(plutil -extract CFBundleIcons xml1 -o - "$plist" 2>/dev/null)" ]]'

manifest="$app/PrivacyInfo.xcprivacy"
check "privacy manifest present" '[[ -f "$manifest" ]]'
check "privacy manifest: no tracking" '[[ "$(plutil -extract NSPrivacyTracking raw -o - "$manifest")" == false ]]'
check "privacy manifest: no collected data" '[[ "$(plutil -extract NSPrivacyCollectedDataTypes json -o - "$manifest")" == "[]" ]]'

binary="$app/$(value CFBundleExecutable)"
check "executable is arm64 only" '[[ "$(lipo -archs "$binary")" == arm64 ]]'
check "no XCTest or Swift Testing linked" '! otool -L "$binary" | grep -qE "XCTest|/Testing.framework|XCUIAutomation"'
app_min="$(value MinimumOSVersion)"
for framework in "$app"/Frameworks/*.framework; do
  [[ -d "$framework" ]] || continue
  name="$(basename "$framework")"
  fplist="$framework/Info.plist"
  check "$name: version keys" '[[ -n "$(plutil -extract CFBundleShortVersionString raw -o - "$fplist" 2>/dev/null)" && -n "$(plutil -extract CFBundleVersion raw -o - "$fplist" 2>/dev/null)" ]]'
  fmin="$(plutil -extract MinimumOSVersion raw -o - "$fplist" 2>/dev/null)"
  check "$name: minimum iOS $fmin <= app $app_min" '[[ -n "$fmin" ]] && [[ "$(printf "%s\n%s\n" "$fmin" "$app_min" | sort -V | head -n 1)" == "$fmin" ]]'
done
check "no recordings or transcripts inside" '[[ -z "$(find "$app" -type f \( -iname "*.caf" -o -iname "*.wav" -o -iname "*.m4a" -o -iname "*.json" -path "*evaluation*" \) | head -n 1)" ]]'
if [[ -n "$log" ]]; then
  check "English-only scope compiled in (ADR 0029)" 'grep -q -- "-DENGLISH_ONLY_RELEASE" "$log"'
fi

if [[ $failures -gt 0 ]]; then
  echo "$failures check(s) failed."
  exit 1
fi
echo "App Store archive checks passed."
