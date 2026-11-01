#!/usr/bin/env bash
# Prints line coverage per module from the package tests (E7-S8). Information
# only: no threshold fails the build (see docs/testing/compatibility-matrix.md).
#
#   scripts/coverage-summary.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
package="$root/Packages/LemmeTypeKit"
swift test --package-path "$package" --enable-code-coverage >/dev/null 2>&1 || {
  echo "error: the package tests failed; fix them before reading coverage" >&2
  exit 1
}
json="$(swift test --package-path "$package" --show-codecov-path)"
python3 -I - "$json" "$package/Sources" <<'PY'
import json, sys
from collections import defaultdict

data = json.load(open(sys.argv[1]))["data"][0]["files"]
sources = sys.argv[2].rstrip("/") + "/"
modules = defaultdict(lambda: [0, 0])  # covered, total lines
for entry in data:
    name = entry["filename"]
    if not name.startswith(sources):
        continue
    module = name[len(sources):].split("/", 1)[0]
    lines = entry["summary"]["lines"]
    modules[module][0] += lines["covered"]
    modules[module][1] += lines["count"]
print(f"{'Module':<14}{'Lines':>9}{'Covered':>10}{'Coverage':>10}")
total = [0, 0]
for module, (covered, count) in sorted(modules.items()):
    pct = 100 * covered / count if count else 100.0
    print(f"{module:<14}{count:>9}{covered:>10}{pct:>9.1f}%")
    total[0] += covered
    total[1] += count
print(f"{'Measured':<14}{total[1]:>9}{total[0]:>10}{100 * total[0] / max(total[1], 1):>9.1f}%")
import os
missing = sorted(set(os.listdir(sources)) - set(modules))
if missing:
    print(f"\nNo data from `swift test` for: {', '.join(missing)}.")
    print("SwiftPM's merged report only includes some test targets here; the Xcode scheme")
    print("(make test, gatherCoverageData) measures them. Coverage is informational.")
PY
