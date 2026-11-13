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
# The manifest, the App Privacy answers, and the policy agree (E13-S8, docs/release/app-store.md section 4).
collected_types() {
  python3 -I -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); print(" ".join(sorted(i["NSPrivacyCollectedDataType"] for i in d.get("NSPrivacyCollectedDataTypes",[]))))' "$manifest"
}
check "privacy manifest: audio, purchases, and usage data, nothing else" '[[ "$(collected_types)" == "NSPrivacyCollectedDataTypeAudioData NSPrivacyCollectedDataTypeOtherUsageData NSPrivacyCollectedDataTypePurchaseHistory" ]]'

# Cloud speech is part of this release, so a build without a production gateway, or while a launch gate is
# still Open, is refused: it would say one thing and do another.
gateway="$(value LemmeTypeGatewayHost)"
check "production gateway host is set (LEMMETYPE_GATEWAY_HOST)" '[[ -n "$gateway" ]]'
check "gateway host is a plain production host name" '[[ "$gateway" =~ ^[A-Za-z0-9.-]+$ && "$gateway" != *staging* && "$gateway" != *.invalid && "$gateway" != localhost ]]'
check "microphone text names Cloud speech" 'value NSMicrophoneUsageDescription | grep -q "Cloud speech"'
check "every ADR 0031 launch gate is Closed in docs/release/app-store.md" '! sed -n "/^## 9\. Launch gates/,\$p" "$root/docs/release/app-store.md" | grep -qE "\| Open \|"'

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
check "no staging gateway host in the app (Debug only, ADR 0033)" '! grep -aq "speech-gateway-staging" "$binary"'
check "no gateway test-token launch argument in the app (Debug only)" '! grep -aq "LemmeTypeGatewayToken" "$binary"'
check "no recordings or transcripts inside" '[[ -z "$(find "$app" -type f \( -iname "*.caf" -o -iname "*.wav" -o -iname "*.m4a" -o -iname "*.json" -path "*evaluation*" \) | head -n 1)" ]]'
if [[ -n "$log" ]]; then
  check "English-only scope compiled in (ADR 0029)" 'grep -q -- "-DENGLISH_ONLY_RELEASE" "$log"'
fi

if [[ $failures -gt 0 ]]; then
  echo "$failures check(s) failed."
  exit 1
fi
echo "App Store archive checks passed."
