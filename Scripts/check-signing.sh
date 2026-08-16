#!/bin/bash
#
# Reports whether every WhizMe build on this machine presents the SAME code identity
# to macOS. If two builds disagree, each one has to be granted privacy access
# separately — which is what "I have to give permission again after every build" feels
# like from the outside.
#
# Usage:  ./Scripts/check-signing.sh
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_IDENTITY="Whiz.me Local Signing"

requirement_of() {
  codesign -d -r- "$1" 2>/dev/null | sed -n 's/^designated => //p'
}

authority_of() {
  codesign -dvvv "$1" 2>&1 | sed -n 's/^Authority=//p' | head -1
}

report() {
  local label="$1" app="$2"
  [ -d "$app" ] || return 0

  local req auth
  req="$(requirement_of "$app")"
  auth="$(authority_of "$app")"
  [ -z "$auth" ] && auth="(ad-hoc — no certificate)"

  printf '%s\n' "$label"
  printf '  path:        %s\n' "$app"
  printf '  authority:   %s\n' "$auth"
  printf '  requirement: %s\n\n' "${req:-(none)}"

  REQUIREMENTS+=("$req")
  LABELS+=("$label")
}

echo
echo "WhizMe code identity check"
echo "==========================="
echo

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$EXPECTED_IDENTITY"; then
  echo "Signing identity '$EXPECTED_IDENTITY' is present and trusted."
else
  echo "WARNING: '$EXPECTED_IDENTITY' is not a trusted code-signing identity."
  echo "         Xcode will fall back to ad-hoc signing, which changes the app's"
  echo "         identity on every build. Run ./Scripts/setup-signing.sh"
fi
echo

REQUIREMENTS=()
LABELS=()

report "script build (build/)" "$ROOT/build/WhizMe.app"

while IFS= read -r app; do
  config="$(basename "$(dirname "$app")")"
  report "Xcode build ($config)" "$app"
done < <(find "$HOME/Library/Developer/Xcode/DerivedData" \
              -path "*Build/Products/*/WhizMe.app" -maxdepth 5 2>/dev/null)

if [ "${#REQUIREMENTS[@]}" -eq 0 ]; then
  echo "No built copies of WhizMe found. Build first, then re-run."
  exit 0
fi

# Every build must present an identical requirement, and it must be certificate-based.
mismatch=0
first="${REQUIREMENTS[0]}"
for req in "${REQUIREMENTS[@]}"; do
  [ "$req" = "$first" ] || mismatch=1
done

if [ "$mismatch" -eq 1 ]; then
  echo "PROBLEM: builds disagree about their identity, so macOS treats them as"
  echo "         different apps and each needs its own permission grant."
  exit 1
fi

case "$first" in
  *cdhash*)
    echo "PROBLEM: the requirement is a cdhash — a hash of the binary itself."
    echo "         It changes on every build, so every build needs re-granting."
    echo "         Fix: ./Scripts/setup-signing.sh"
    exit 1
    ;;
  *certificate*)
    echo "OK: all builds share one certificate-based identity."
    echo "    A permission granted to one build applies to the next."
    ;;
  *)
    echo "Unrecognised requirement — inspect manually with: codesign -d -r- <app>"
    exit 1
    ;;
esac
