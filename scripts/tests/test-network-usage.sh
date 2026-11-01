#!/usr/bin/env bash
# Fixture tests for scripts/check-network-usage.sh (E6-S2).
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
script="$repo/scripts/check-network-usage.sh"
failures=0

fixture() { # fixture <allowlist line> -> prints the fixture root
  local dir; dir="$(mktemp -d)"
  mkdir -p "$dir/docs/security" "$dir/App/LemmeType" "$dir/Packages/LemmeTypeKit/Sources/Domain"
  printf '%s\n' "# test" "$1" > "$dir/docs/security/network-allowlist.txt"
  echo "$dir"
}

expect() { # expect <name> <pass|fail> <root>
  local name="$1" want="$2" root="$3" got
  if "$script" --root "$root" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name (wanted $want, got $got)"; failures=$((failures + 1)); fi
  rm -rf "$root"
}

root="$(fixture '')"
echo 'struct Clean { func run() {} }' > "$root/App/LemmeType/Clean.swift"
expect "clean tree passes" pass "$root"

root="$(fixture '')"
echo 'let session = URLSession.shared' > "$root/Packages/LemmeTypeKit/Sources/Domain/Leak.swift"
expect "URLSession outside the allowlist fails" fail "$root"

root="$(fixture 'App/LemmeType/Net.swift  # test')"
echo 'let session = URLSession.shared' > "$root/App/LemmeType/Net.swift"
expect "URLSession in an allowlisted file passes" pass "$root"

root="$(fixture '')"
printf 'import Network\n' > "$root/App/LemmeType/Imp.swift"
expect "import Network fails" fail "$root"

root="$(fixture '')"
printf 'let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")\n' > "$root/App/LemmeType/Tool.swift"
expect "launching curl fails" fail "$root"

root="$(fixture '')"
printf 'let fd = socket(AF_INET, SOCK_STREAM, 0)\n' > "$root/App/LemmeType/Raw.swift"
expect "a raw socket call fails" fail "$root"

root="$(fixture '')"
printf '// URLSession is described here but never used\nstruct URLSessionModelDownloader {}\nfunc reconnect() {}\n' > "$root/App/LemmeType/Doc.swift"
expect "comments and longer names pass" pass "$root"

root="$(fixture 'App/LemmeType/Gone.swift  # stale')"
expect "a stale allowlist entry fails" fail "$root"

# The real repository must pass today.
if "$script" >/dev/null 2>&1; then echo "ok   repository passes"; else echo "FAIL repository passes"; failures=$((failures + 1)); fi

[[ $failures -eq 0 ]] && echo "All network-usage checks passed." || { echo "$failures failure(s)."; exit 1; }
