#!/usr/bin/env bash
# Fixture tests for scripts/verify-release.sh and notarize-release.sh (E7-S2).
# Builds tiny signed fake apps in a temporary folder and seeds one violation at a time.
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
verify="$repo/scripts/verify-release.sh"
# Not named LemmeTypeTests-*: check-release-artifact.sh treats that as leaked test output.
work="$(mktemp -d "${TMPDIR:-/tmp}/verify-release-fixture-XXXXXX")"
trap 'rm -rf "$work"' EXIT
failures=0

# A fixture "repository": the version file, the entitlement allowlist, and the artifact check.
root="$work/root"
mkdir -p "$root/Config" "$root/docs/security" "$root/scripts"
printf 'MARKETING_VERSION = 1.2.3\nCURRENT_PROJECT_VERSION = 45\n' > "$root/Config/Version.xcconfig"
cp "$repo/docs/security/entitlements-allowlist.txt" "$root/docs/security/"
cp "$repo/scripts/check-release-artifact.sh" "$root/scripts/"

echo 'int main(void) { return 0; }' | clang -arch arm64 -x c - -o "$work/fake-binary" 2>/dev/null
echo 'int value(void) { return 1; }' | clang -arch arm64 -dynamiclib -x c - -o "$work/libfake.dylib" 2>/dev/null

audio_entitlements="$work/audio.entitlements"
cat > "$audio_entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.device.audio-input</key><true/></dict></plist>
PLIST

# make_app <name> [runtime=yes|no] [entitlements file] [version]
make_app() {
  local app="$work/$1.app" runtime="${2:-yes}" ents="${3:-$audio_entitlements}" version="${4:-1.2.3}"
  rm -rf "$app"
  mkdir -p "$app/Contents/MacOS"
  cp "$work/fake-binary" "$app/Contents/MacOS/LemmeType"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LemmeType</string>
<key>CFBundleIdentifier</key><string>com.lemmetype.LemmeType</string>
<key>CFBundleShortVersionString</key><string>$version</string>
<key>CFBundleVersion</key><string>45</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Dictation.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>Speech.</string>
</dict></plist>
PLIST
  echo "$app"
}

sign() { # sign <app> [runtime yes|no] [entitlements]
  local options=()
  [[ "${2:-yes}" == "yes" ]] && options+=(--options runtime)
  [[ -n "${3:-}" ]] && options+=(--entitlements "$3")
  codesign --force --sign - "${options[@]}" "$1" >/dev/null 2>&1
}

expect() { # expect <name> <pass|fail> <app> [extra args]
  local name="$1" want="$2" app="$3"; shift 3
  local out got
  out="$("$verify" "$app" --rehearsal --root "$root" "$@" 2>&1)"
  if [[ $? -eq 0 ]]; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (wanted $want, got $got)"; echo "$out" | sed 's/^/       /'; failures=$((failures + 1)); fi
}

app="$(make_app good)"; sign "$app" yes "$audio_entitlements"
expect "a hardened, correctly signed app passes" pass "$app"

app="$(make_app norunt)"; sign "$app" no "$audio_entitlements"
expect "missing Hardened Runtime fails" fail "$app"

extra="$work/extra.entitlements"
sed 's|</dict>|<key>com.apple.security.network.client</key><true/></dict>|' "$audio_entitlements" > "$extra"
app="$(make_app extra)"; sign "$app" yes "$extra"
expect "an extra entitlement fails" fail "$app"

debug="$work/debug.entitlements"
sed 's|</dict>|<key>com.apple.security.get-task-allow</key><true/></dict>|' "$audio_entitlements" > "$debug"
app="$(make_app debugbuild)"; sign "$app" yes "$debug"
expect "get-task-allow fails" fail "$app"

app="$(make_app noents)"; sign "$app" yes ""
expect "a missing entitlement fails" fail "$app"

app="$(make_app version "yes" "$audio_entitlements" "9.9.9")"; sign "$app" yes "$audio_entitlements"
expect "a version that differs from Version.xcconfig fails" fail "$app"

app="$(make_app unsigned)"
expect "an unsigned app fails" fail "$app"

app="$(make_app badframework)"; sign "$app" yes "$audio_entitlements"
mkdir -p "$app/Contents/Frameworks"; cp "$work/libfake.dylib" "$app/Contents/Frameworks/libfake.dylib"
expect "an unsigned embedded library fails" fail "$app"

app="$(make_app goodframework)"
mkdir -p "$app/Contents/Frameworks"; cp "$work/libfake.dylib" "$app/Contents/Frameworks/libfake.dylib"
codesign --force --sign - --options runtime "$app/Contents/Frameworks/libfake.dylib" >/dev/null 2>&1
sign "$app" yes "$audio_entitlements"
expect "a signed embedded library passes" pass "$app"

app="$(make_app recording)"
mkdir -p "$app/Contents/Resources"; echo audio > "$app/Contents/Resources/dictation.caf"
sign "$app" yes "$audio_entitlements"
expect "a bundled recording fails" fail "$app"

# The zip form is verified too.
app="$(make_app zipped)"; sign "$app" yes "$audio_entitlements"
ditto -c -k --keepParent "$app" "$work/zipped.zip"
expect "a zip of a good app passes" pass "$work/zipped.zip"

# Without --rehearsal an ad-hoc app is rejected by Gatekeeper and has no ticket.
if "$verify" "$work/good.app" --root "$root" >/dev/null 2>&1; then
  echo "FAIL a non-rehearsal check accepted an un-notarized app"; failures=$((failures + 1))
else echo "ok   an un-notarized app fails outside rehearsal mode"; fi

# notarize-release.sh never claims success without a profile.
out="$(env -u NOTARY_PROFILE "$repo/scripts/notarize-release.sh" 2>&1)"; code=$?
if [[ $code -eq 3 && "$out" == *"NOT NOTARIZED"* ]]; then echo "ok   notarize without a profile says NOT NOTARIZED (exit 3)"; else
  echo "FAIL notarize without a profile (exit $code): $out"; failures=$((failures + 1)); fi
out="$(NOTARY_PROFILE=example-profile "$repo/scripts/notarize-release.sh" --dry-run 2>&1)"; code=$?
if [[ $code -eq 0 && "$out" == *"would run: xcrun notarytool submit"* && "$out" == *"would run: xcrun stapler staple"* && "$out" == *"Dry run: nothing was submitted."* ]]; then
  echo "ok   notarize --dry-run lists the steps and submits nothing"; else
  echo "FAIL notarize --dry-run (exit $code): $out"; failures=$((failures + 1)); fi

[[ $failures -eq 0 ]] && echo "All release-verification checks passed." || { echo "$failures failure(s)."; exit 1; }
