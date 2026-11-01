#!/usr/bin/env bash
# Packages build/release/export/LemmeType.app into a zip, a disk image, and
# SHA-256 checksums (E7-S2, ADR 0026). Run again after stapling so the shipped
# files contain the stapled app.
#
#   scripts/package-release.sh [--root <repository root>]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == "--root" ]]; then root="$(cd "${2:?--root needs a directory}" && pwd)"; fi

out="$root/build/release"
app="$out/export/LemmeType.app"
[[ -d "$app" ]] || { echo "error: $app not found; run scripts/build-release.sh first" >&2; exit 2; }

version="$(sed -n 's/^MARKETING_VERSION[[:space:]]*=[[:space:]]*//p' "$root/Config/Version.xcconfig" | tr -d '[:space:]')"
[[ -n "$version" ]] || { echo "error: MARKETING_VERSION not found in Config/Version.xcconfig" >&2; exit 2; }

zip="$out/LemmeType-$version.zip"
dmg="$out/LemmeType-$version.dmg"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT

rm -f "$zip" "$dmg" "$out/SHA256SUMS"
ditto -c -k --keepParent "$app" "$zip"

ditto "$app" "$staging/LemmeType.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "LemmeType $version" -srcfolder "$staging" -ov -format UDZO "$dmg"

(cd "$out" && shasum -a 256 "$(basename "$zip")" "$(basename "$dmg")" > SHA256SUMS)
echo "Packaged:"
cat "$out/SHA256SUMS"
