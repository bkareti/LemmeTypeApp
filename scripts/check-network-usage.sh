#!/usr/bin/env bash
# Static network check (E6-S2, ADR 0025): fails when a source file that is not
# listed in docs/security/network-allowlist.txt uses a network API.
#
#   scripts/check-network-usage.sh [--root <repository root>]
#
# Scans production Swift code (App/ and Packages/LemmeTypeKit/Sources/). Lines
# that are only a comment are ignored. Every allowlisted file must exist, so a
# renamed or deleted file cannot leave a stale permission behind.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == "--root" ]]; then root="$(cd "${2:?--root needs a directory}" && pwd)"; fi

allowlist="$root/docs/security/network-allowlist.txt"
[[ -f "$allowlist" ]] || { echo "error: missing $allowlist" >&2; exit 2; }

# Whole-word API names, imports, raw socket and name-resolution calls, and
# processes that talk to the network.
symbols='URLSession|URLRequest|NSURLConnection|NSURLSession|NWConnection|NWListener|NWBrowser|NWPathMonitor|CFSocket|CFHTTPMessage|CFReadStream|CFWriteStream|WKWebView|MultipeerConnectivity'
calls='(socket|getaddrinfo|gethostbyname|connect)[[:space:]]*\('
imports='import[[:space:]]+(Network|CFNetwork|MultipeerConnectivity)'
tools='"(/usr/bin/)?(curl|wget|nc|ncat|ssh|scp|ftp|telnet)"'
pattern="(^|[^A-Za-z0-9_])(${symbols})([^A-Za-z0-9_]|\$)|(^|[^A-Za-z0-9_.])(${calls})|${imports}|${tools}"

allowed=()
while IFS= read -r line; do
  path="$(printf '%s' "${line%%#*}" | sed 's/[[:space:]]*$//; s/^[[:space:]]*//')"
  [[ -n "$path" ]] && allowed+=("$path")
done < "$allowlist"

status=0
for path in ${allowed[@]+"${allowed[@]}"}; do
  if [[ ! -f "$root/$path" ]]; then
    echo "error: the allowlist names a file that does not exist: $path" >&2
    status=1
  fi
done

is_allowed() {
  local file="$1" path
  for path in ${allowed[@]+"${allowed[@]}"}; do [[ "$path" == "$file" ]] && return 0; done
  return 1
}

found=""
while IFS= read -r -d '' file; do
  relative="${file#"$root"/}"
  hits="$(grep -nE -- "$pattern" "$file" | grep -vE '^[0-9]+:[[:space:]]*//' || true)"
  if [[ -n "$hits" ]] && ! is_allowed "$relative"; then
    found+="$(printf '%s\n' "$hits" | sed "s|^|$relative:|")"$'\n'
  fi
done < <(find "$root/App" "$root/Packages/LemmeTypeKit/Sources" -type f \( -name '*.swift' -o -name '*.m' -o -name '*.mm' -o -name '*.c' \) -print0 2>/dev/null)

if [[ -n "$found" ]]; then
  echo "error: network APIs are used outside docs/security/network-allowlist.txt:" >&2
  printf '%s' "$found" >&2
  echo "Local mode must stay network-silent. See docs/decisions/0025-privacy-data-and-history.md." >&2
  status=1
fi

if [[ $status -eq 0 ]]; then
  echo "Network APIs are used only by the ${#allowed[@]} allowlisted file(s)."
fi
exit "$status"
