#!/usr/bin/env bash
# Makes the App Store screenshots of the iPhone and iPad app (docs/release/app-store.md)
# on the 6.9-inch iPhone and 13-inch iPad simulators, with Apple's standard status bar,
# from AppStoreScreenshotsUITests, built English-only like the release (ADR 0029). Writes build/app-store-screenshots/<device>/NN-name.png
# and checks each image has a size App Store Connect accepts.
#
#   scripts/make-app-store-screenshots.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
out="$root/build/app-store-screenshots"
rm -rf "$out"
mkdir -p "$out"
xcodegen generate --quiet

# device name | accepted portrait sizes (App Store Connect, 2026)
devices=(
  "iPhone 18 Pro Max|1320x2868 1290x2796"
  "iPad Pro 13-inch (M5)|2064x2752 2048x2732"
)
failures=0
for entry in "${devices[@]}"; do
  name="${entry%%|*}"
  sizes="${entry#*|}"
  udid="$(xcrun simctl list devices available | grep -F "    $name (" | head -n 1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')"
  [[ -n "$udid" ]] || { echo "error: no simulator named $name" >&2; exit 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b > /dev/null
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
  slug="$(echo "$name" | tr -cs '[:alnum:]' '-' | sed 's/-$//')"
  bundle="$out/$slug.xcresult"
  TEST_RUNNER_LEMMETYPE_SCREENSHOTS=1 xcodebuild test -project LemmeType.xcodeproj -scheme LemmeTypeiOS \
    -destination "id=$udid" -derivedDataPath build/DerivedData-ios-screens -resultBundlePath "$bundle" \
    -only-testing:LemmeTypeiOSUITests/AppStoreScreenshotsUITests \
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG ENGLISH_ONLY_RELEASE" > "$out/$slug.log" 2>&1 \
    || { tail -n 20 "$out/$slug.log" >&2; echo "error: screenshot run failed on $name" >&2; exit 1; }
  raw="$out/$slug-raw"
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$raw" > /dev/null
  mkdir -p "$out/$slug"
  python3 -I - "$raw" "$out/$slug" <<'PY'
import json, shutil, sys
raw, dest = sys.argv[1], sys.argv[2]
for test in json.load(open(f"{raw}/manifest.json")):
    for item in test.get("attachments", []):
        label = item.get("suggestedHumanReadableName", "")
        name = label.split("_")[0]
        if name[:2].isdigit():
            shutil.copy(f"{raw}/{item['exportedFileName']}", f"{dest}/{name}.png")
PY
  rm -rf "$raw"
  xcrun simctl status_bar "$udid" clear
  for png in "$out/$slug"/*.png; do
    size="$(sips -g pixelWidth -g pixelHeight "$png" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
    if [[ " $sizes " == *" $size "* ]]; then echo "ok    $name $(basename "$png") $size"
    else echo "FAIL  $name $(basename "$png") $size (App Store accepts $sizes)"; failures=$((failures + 1)); fi
  done
done
[[ $failures -eq 0 ]] || exit 1
echo "Screenshots: $out"
