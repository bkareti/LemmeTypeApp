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
testflight_only=0
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
# The release scope (LEMMETYPE_RELEASE_SCOPE in Config/LemmeTypeiOS.xcconfig) decides what the build may do, and
# the manifest, the microphone text, and the App Privacy answers must say the same (docs/release/app-store.md,
# "Release scope" and section 4). A build that says one thing and does another is refused.
collected_types() {
  python3 -I -c 'import plistlib,sys; d=plistlib.load(open(sys.argv[1],"rb")); print(" ".join(sorted(i["NSPrivacyCollectedDataType"] for i in d.get("NSPrivacyCollectedDataTypes",[]))))' "$manifest"
}
scope="$(value LemmeTypeReleaseScope)"
gateway="$(value LemmeTypeGatewayHost)"
check "release scope is local or cloud (LEMMETYPE_RELEASE_SCOPE)" '[[ "$scope" == local || "$scope" == cloud ]]'
if [[ "$scope" == cloud ]]; then
  # Cloud speech is part of this release, so a build without a production gateway, or while a launch gate is
  # still Open, is refused.
  check "privacy manifest: audio, purchases, and usage data, nothing else" '[[ "$(collected_types)" == "NSPrivacyCollectedDataTypeAudioData NSPrivacyCollectedDataTypeOtherUsageData NSPrivacyCollectedDataTypePurchaseHistory" ]]'
  check "production gateway host is set (LEMMETYPE_GATEWAY_HOST)" '[[ -n "$gateway" ]]'
  check "gateway host is a plain production host name" '[[ "$gateway" =~ ^[A-Za-z0-9.-]+$ && "$gateway" != *staging* && "$gateway" != *.invalid && "$gateway" != localhost ]]'
  check "microphone text names Cloud speech" 'value NSMicrophoneUsageDescription | grep -q "Cloud speech"'
  gates_closed='! sed -n "/^## 9\. Launch gates/,\$p" "$root/docs/release/app-store.md" | grep -qE "\| Open \|"'
  if [[ "${TESTFLIGHT_ONLY:-}" == 1 ]] && ! eval "$gates_closed"; then
    # TestFlight-only upload (make ios-appstore UPLOAD=1 TESTFLIGHT=1): testers may use Cloud speech before every
    # gate is Closed. The build must not be submitted for App Review until this check passes without TESTFLIGHT.
    printf 'WARN  %s\n' "launch gates still Open: allowed for TestFlight only (TESTFLIGHT_ONLY=1); App Review needs them Closed"
    testflight_only=1
  else
    check "every ADR 0031 launch gate is Closed in docs/release/app-store.md" "$gates_closed"
  fi
  check "cloud scope: the App Store text is for the cloud scope" 'grep -q "^Release scope: \*\*cloud\*\*" "$root/docs/release/app-store.md"'
else
  # Version 1.0: Local dictation only. Nothing is sent to LemmeType, so nothing is declared as collected.
  check "local scope: privacy manifest declares no collected data" '[[ -z "$(collected_types)" ]]'
  check "local scope: no gateway host (LEMMETYPE_GATEWAY_HOST is empty)" '[[ -z "$gateway" ]]'
  check "local scope: microphone text does not mention Cloud" '! value NSMicrophoneUsageDescription | grep -qi "cloud"'
  check "local scope: the App Store text is for the local scope" 'grep -q "^Release scope: \*\*local\*\*" "$root/docs/release/app-store.md"'
fi

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
if [[ "${testflight_only:-}" == 1 ]]; then
  echo "Archive checks passed for TESTFLIGHT ONLY. Do not submit this build for App Review: launch gates are Open."
  exit 0
fi
echo "App Store archive checks passed."
