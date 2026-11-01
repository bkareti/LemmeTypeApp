#!/usr/bin/env bash
# Verifies a built LemmeType app, zip, or disk image (E7-S2, ADR 0026).
#
#   scripts/verify-release.sh <LemmeType.app | .zip | .dmg> [--rehearsal] [--root <repo root>]
#
# Checks: bundle id, version and build equal Config/Version.xcconfig, minimum
# macOS, menu-bar agent, privacy usage strings, arm64 only, a valid deep and
# strict code signature, Hardened Runtime, entitlements equal to
# docs/security/entitlements-allowlist.txt (and never get-task-allow), and no
# recordings, transcripts, or benchmark output (check-release-artifact.sh).
# Without --rehearsal it also requires a Gatekeeper-accepted, stapled app, so a
# build that was not notarized fails. Exits non-zero on any failure.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
target=""
rehearsal=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rehearsal) rehearsal=1 ;;
    --root) root="$(cd "${2:?--root needs a directory}" && pwd)"; shift ;;
    *) target="$1" ;;
  esac
  shift
done
[[ -n "$target" ]] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

work=""
mounted=""
cleanup() {
  [[ -n "$mounted" ]] && hdiutil detach -quiet "$mounted" 2>/dev/null
  [[ -n "$work" ]] && rm -rf "$work"
  return 0
}
trap cleanup EXIT

case "$target" in
  *.zip) work="$(mktemp -d)"; ditto -x -k "$target" "$work"; app="$(find "$work" -maxdepth 2 -name '*.app' -print -quit)" ;;
  *.dmg) mounted="$(mktemp -d)"; hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mounted" "$target" || exit 2
         app="$(find "$mounted" -maxdepth 2 -name '*.app' -print -quit)" ;;
  *) app="$target" ;;
esac
[[ -d "${app:-}" ]] || { echo "error: no .app found in $target" >&2; exit 2; }

failures=0
ok() { echo "ok    $1"; }
bad() { echo "FAIL  $1" >&2; failures=$((failures + 1)); }
check() { # check <description> <command…>
  local description="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$description"; else bad "$description"; fi
}

plist="$app/Contents/Info.plist"
read_plist() { plutil -extract "$1" raw -o - "$plist" 2>/dev/null; }
setting() { sed -n "s/^$1[[:space:]]*=[[:space:]]*//p" "$root/Config/Version.xcconfig" | tr -d '[:space:]'; }

expect_equal() { # expect_equal <description> <actual> <expected>
  if [[ "$2" == "$3" && -n "$3" ]]; then ok "$1 ($2)"; else bad "$1 (found '$2', expected '$3')"; fi
}

expect_equal "bundle identifier" "$(read_plist CFBundleIdentifier)" "com.lemmetype.LemmeType"
expect_equal "version equals Config/Version.xcconfig" "$(read_plist CFBundleShortVersionString)" "$(setting MARKETING_VERSION)"
expect_equal "build equals Config/Version.xcconfig" "$(read_plist CFBundleVersion)" "$(setting CURRENT_PROJECT_VERSION)"
expect_equal "minimum macOS" "$(read_plist LSMinimumSystemVersion)" "26.0"
expect_equal "menu-bar agent (LSUIElement)" "$(read_plist LSUIElement)" "true"
for key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription; do
  [[ -n "$(read_plist "$key")" ]] && ok "$key present" || bad "$key missing"
done

executable="$app/Contents/MacOS/$(read_plist CFBundleExecutable)"
expect_equal "architectures" "$(lipo -archs "$executable" 2>/dev/null)" "arm64"

if codesign --verify --deep --strict "$app" 2>/dev/null; then ok "code signature is valid (deep, strict)"; else bad "code signature is invalid or incomplete (an embedded item may be unsigned)"; fi

details="$(codesign -dv --verbose=4 "$app" 2>&1)"
if grep -Eq 'flags=0x[0-9a-f]+\([^)]*runtime' <<<"$details"; then ok "Hardened Runtime is on"; else bad "Hardened Runtime is off"; fi

# Entitlements must equal the reviewed allowlist, and never include get-task-allow.
allowed="$(sed 's/#.*//; s/[[:space:]]*$//; s/^[[:space:]]*//' "$root/docs/security/entitlements-allowlist.txt" | grep -v '^$' | sort)"
actual="$(codesign -d --entitlements - --xml "$app" 2>/dev/null | python3 -I -c '
import plistlib, sys
data = sys.stdin.buffer.read()
start = data.find(b"<?xml")
print("\n".join(sorted(plistlib.loads(data[start:]))) if start >= 0 else "", end="")
' 2>/dev/null)"
if [[ "$actual" == "$allowed" ]]; then ok "entitlements equal the allowlist"; else
  bad "entitlements differ from docs/security/entitlements-allowlist.txt"
  diff <(echo "$allowed") <(echo "$actual") | sed 's/^/        /' >&2
fi
if grep -q 'get-task-allow' <<<"$actual"; then bad "get-task-allow is present (a development build)"; else ok "no get-task-allow"; fi

if "$root/scripts/check-release-artifact.sh" "$app" >/dev/null 2>&1; then ok "no recordings, transcripts, or benchmark output"; else
  bad "the bundle contains recordings, transcripts, or benchmark output"
fi

if [[ $rehearsal -eq 1 ]]; then
  echo "skip  Gatekeeper and notarization (rehearsal build)"
else
  if spctl --assess --type execute "$app" 2>/dev/null; then ok "Gatekeeper accepts the app"; else bad "Gatekeeper rejects the app (not notarized?)"; fi
  if xcrun stapler validate "$app" >/dev/null 2>&1; then ok "notarization ticket is stapled"; else bad "no stapled notarization ticket"; fi
fi

if [[ $failures -eq 0 ]]; then
  echo "Release artifact verified$([[ $rehearsal -eq 1 ]] && echo " (rehearsal: not notarized)")."
else
  echo "$failures check(s) failed." >&2
  exit 1
fi
