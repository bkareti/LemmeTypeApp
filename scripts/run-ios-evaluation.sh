#!/bin/sh
# Runs the corpus evaluation inside the iPhone and iPad app (Debug build), on the iOS Simulator
# or a connected device, then writes the summary, JUnit XML, and HTML dashboard
# (docs/testing/evaluation-harness.md, "On iPhone and iPad").
#
#   scripts/run-ios-evaluation.sh --model <id> [options]
#
#   --model ID           a Whisper model id from the catalog, such as whisper-base (required)
#   --device ID          a connected iPhone or iPad (name or UDID); default: the Simulator
#   --simulator NAME     the Simulator to use (default: iPhone 17)
#   --manifests LIST     manifests in docs/testing/corpus (default: fleurs.json,edge-cases.json)
#   --corpus-root DIR    the fetched FLEURS folder (default: the pinned folder in the cache)
#   --languages LIST     such as hi,te; on a device only those folders are copied
#   --task, --mode, --style, --label   as in the Mac run (scripts/run-evaluation.sh)
#   --copy-mac-model     put this Mac's installed copy of the model into the app (verified by
#                        SHA-256 at load); otherwise install it in the app's Settings › Models
#   --timeout SECONDS    how long to wait for the app (default: 7200)
#   --skip-build         use the last build
#
# Only metrics come back, to build/evaluation/ios/. The app deletes the copied manifests and
# audio when it finishes. A device run should be made in Airplane Mode: iOS has no socket watch.
set -eu
cd "$(dirname "$0")/.."

BUNDLE=com.lemmetype.LemmeType.iOS
MODEL=""
DEVICE=""
SIMULATOR="iPhone 17"
MANIFESTS="fleurs.json,edge-cases.json"
ROOT="$HOME/Library/Caches/LemmeTypeCorpus/fleurs/70bb2e84b976b7e960aa89f1c648e09c59f894dd"
LANGUAGES=""
COPY_MODEL=0
TIMEOUT=7200
BUILD=1
APP_ARGS=""

while [ $# -gt 0 ]; do
    case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --simulator) SIMULATOR="$2"; shift 2 ;;
    --manifests) MANIFESTS="$2"; shift 2 ;;
    --corpus-root) ROOT="$2"; shift 2 ;;
    --languages) LANGUAGES="$2"; APP_ARGS="$APP_ARGS -LemmeTypeEvaluationLanguages $2"; shift 2 ;;
    --task) APP_ARGS="$APP_ARGS -LemmeTypeEvaluationTask $2"; shift 2 ;;
    --mode) APP_ARGS="$APP_ARGS -LemmeTypeEvaluationMode $2"; shift 2 ;;
    --style) APP_ARGS="$APP_ARGS -LemmeTypeEvaluationStyle $2"; shift 2 ;;
    --label) APP_ARGS="$APP_ARGS -LemmeTypeEvaluationLabel $2"; shift 2 ;;
    --copy-mac-model) COPY_MODEL=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --skip-build) BUILD=0; shift ;;
    *) echo "unknown option: $1" >&2; exit 64 ;;
    esac
done
[ -n "$MODEL" ] || { echo "--model is required (such as whisper-base)" >&2; exit 64; }

OUT=build/evaluation/ios
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/LemmeTypeTests-IOSEvaluation.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUT" "$STAGE/LemmeTypeEvaluation/manifests"
rm -f "$OUT"/*.json  # reports of an earlier run would be summarised with this one

# The manifests, and a check that the corpus audio matches them.
for name in $(echo "$MANIFESTS" | tr ',' ' '); do
    cp "docs/testing/corpus/$name" "$STAGE/LemmeTypeEvaluation/manifests/"
    if [ "$name" = fleurs.json ]; then
        python3 -I scripts/corpus.py verify "docs/testing/corpus/$name" --root "$ROOT"
    fi
done

MAC_MODEL="$HOME/Library/Application Support/LemmeType/Models/$MODEL"
if [ "$COPY_MODEL" = 1 ] && [ ! -d "$MAC_MODEL" ]; then
    echo "$MODEL is not installed in LemmeType on this Mac" >&2
    exit 1
fi

if [ -z "$DEVICE" ]; then
    # --- iOS Simulator --------------------------------------------------------------------
    UDID=$(xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for runtime, devices in json.load(sys.stdin)["devices"].items():
    for device in devices:
        if device["name"] == name and "iOS" in runtime:
            print(device["udid"]); sys.exit(0)
sys.exit(1)' "$SIMULATOR") || { echo "no available Simulator named $SIMULATOR" >&2; exit 1; }
    xcrun simctl boot "$UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null
    if [ "$BUILD" = 1 ]; then
        make generate >/dev/null
        xcodebuild -quiet -project LemmeType.xcodeproj -scheme LemmeTypeiOS -configuration Debug \
            -destination "id=$UDID" -derivedDataPath build/DerivedData-ios build
    fi
    xcrun simctl install "$UDID" build/DerivedData-ios/Build/Products/Debug-iphonesimulator/LemmeType.app
    CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
    FOLDER="$CONTAINER/Documents/LemmeTypeEvaluation"
    rm -rf "$FOLDER"
    mkdir -p "$CONTAINER/Documents"
    cp -R "$STAGE/LemmeTypeEvaluation" "$FOLDER"
    # The Simulator shares this Mac's disk: a link, so no audio is copied.
    ln -s "$ROOT" "$FOLDER/corpus"
    if [ "$COPY_MODEL" = 1 ]; then
        MODELS="$CONTAINER/Library/Application Support/LemmeType/Models"
        mkdir -p "$MODELS"
        rm -rf "${MODELS:?}/$MODEL"
        cp -cR "$MAC_MODEL" "$MODELS/"
    fi
    # shellcheck disable=SC2086 # APP_ARGS is a list of flags and values without spaces
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -LemmeTypeEvaluation "$MODEL" $APP_ARGS >/dev/null
    waited=0
    until [ -f "$FOLDER/status.json" ]; do
        [ "$waited" -lt "$TIMEOUT" ] || { echo "the app did not finish within $TIMEOUT s" >&2; exit 1; }
        sleep 5
        waited=$((waited + 5))
        # The app writes a status before it quits; if it is gone without one, it crashed.
        if [ ! -f "$FOLDER/status.json" ] &&
            ! xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep "UIKitApplication:$BUNDLE" >/dev/null; then
            rm -rf "$FOLDER"
            echo "the app ended without a status (a crash?); see ~/Library/Logs/DiagnosticReports" >&2
            exit 1
        fi
    done
    cp "$FOLDER/status.json" "$OUT/status.json"
    cp "$FOLDER"/reports/*.json "$OUT/" 2>/dev/null || true
    rm -rf "$FOLDER"
else
    # --- A connected iPhone or iPad (signing as set up in Xcode) ----------------------------
    if [ -n "$LANGUAGES" ]; then
        mkdir -p "$STAGE/LemmeTypeEvaluation/corpus"
        for code in $(echo "$LANGUAGES" | tr ',' ' '); do
            for folder in "$ROOT/${code}"_*; do
                [ -d "$folder" ] && cp -R "$folder" "$STAGE/LemmeTypeEvaluation/corpus/"
            done
        done
    else
        cp -R "$ROOT" "$STAGE/LemmeTypeEvaluation/corpus"
    fi
    if [ "$BUILD" = 1 ]; then
        make generate >/dev/null
        xcodebuild -quiet -project LemmeType.xcodeproj -scheme LemmeTypeiOS -configuration Debug \
            -destination "id=$DEVICE" -derivedDataPath build/DerivedData-ios -allowProvisioningUpdates build
    fi
    xcrun devicectl device install app --device "$DEVICE" build/DerivedData-ios/Build/Products/Debug-iphoneos/LemmeType.app
    copy_to() {
        xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer \
            --domain-identifier "$BUNDLE" --source "$1" --destination "$2" >/dev/null
    }
    copy_from() {
        xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
            --domain-identifier "$BUNDLE" --source "$1" --destination "$2" >/dev/null 2>&1
    }
    copy_to "$STAGE/LemmeTypeEvaluation" Documents/LemmeTypeEvaluation
    if [ "$COPY_MODEL" = 1 ]; then
        copy_to "$MAC_MODEL" "Library/Application Support/LemmeType/Models/$MODEL"
    fi
    # shellcheck disable=SC2086
    xcrun devicectl device process launch --device "$DEVICE" --terminate-existing "$BUNDLE" \
        -LemmeTypeEvaluation "$MODEL" $APP_ARGS >/dev/null
    waited=0
    until copy_from Documents/LemmeTypeEvaluation/status.json "$OUT/status.json"; do
        [ "$waited" -lt "$TIMEOUT" ] || { echo "the app did not finish within $TIMEOUT s" >&2; exit 1; }
        sleep 15
        waited=$((waited + 15))
    done
    copy_from Documents/LemmeTypeEvaluation/reports "$STAGE/reports" || true
    cp "$STAGE"/reports/*.json "$OUT/" 2>/dev/null || true
fi

cat "$OUT/status.json"
echo
python3 -I -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1]))["status"] == "done" else 1)' "$OUT/status.json"
rm "$OUT/status.json"
python3 -I scripts/evaluation-report.py "$OUT" --out "$OUT/report"
scripts/check-no-captured-audio.sh
