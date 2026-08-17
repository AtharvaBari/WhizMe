#!/bin/bash
#
# Erases every trace of WhizMe from this Mac, so the next launch is a genuine first run:
# the full-screen welcome plays, and the permission walkthrough follows because nothing
# has been granted yet.
#
# Usage:
#   ./Scripts/reset-local-state.sh                    everything
#   ./Scripts/reset-local-state.sh --keep-permissions  state only, keep TCC grants
#   ./Scripts/reset-local-state.sh --clean-build       also wipe DerivedData and build/
#
# WHAT THIS DOES NOT TOUCH — and must never touch:
#
#   * The "Whiz.me Local Signing" certificate in the login keychain.
#   * The Sparkle EdDSA private key in the login keychain.
#
# Both are irreplaceable. Losing the certificate drops the privacy grants of every
# installed copy AND makes Sparkle reject all future updates; losing the Sparkle key means
# no further update can ever be published. Neither is app state, so neither belongs in a
# state reset — see the key table in README.md.
#
set -euo pipefail

BUNDLE_ID="me.whiz.app"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

KEEP_PERMISSIONS=0
CLEAN_BUILD=0
for arg in "$@"; do
  case "$arg" in
    --keep-permissions) KEEP_PERMISSIONS=1 ;;
    --clean-build) CLEAN_BUILD=1 ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

echo "==> Quitting WhizMe"
# Must happen first. A running app flushes its UserDefaults on exit, so deleting the
# domain underneath it just gets everything written straight back.
pkill -x WhizMe 2>/dev/null || true
# Give termination a moment to complete, otherwise the flush races the delete below.
for _ in $(seq 1 20); do
  pgrep -x WhizMe >/dev/null || break
  sleep 0.1
done

echo "==> Removing preferences"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f "$HOME/Library/Preferences/$BUNDLE_ID.plist"
# cfprefsd caches preference domains in memory and will happily rewrite the file it still
# believes in. Deleting the plist without this is the classic reason "reset" appears to do
# nothing. Scoped to this user's daemon; it relaunches on demand.
killall -u "$USER" cfprefsd 2>/dev/null || true

echo "==> Removing caches and saved state"
rm -rf "$HOME/Library/Caches/$BUNDLE_ID" \
       "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
       "$HOME/Library/HTTPStorages/$BUNDLE_ID.binarycookies" \
       "$HOME/Library/Application Support/$BUNDLE_ID" \
       "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
       "$HOME/Library/WebKit/$BUNDLE_ID"

if [ "$KEEP_PERMISSIONS" -eq 0 ]; then
  echo "==> Resetting privacy permissions"
  # Each of these is a service WhizMe asks for. Resetting means macOS will prompt again,
  # which is the point: it is the only way to see the permission walkthrough.
  for service in ScreenCapture Accessibility AppleEvents PostEvent ListenEvent; do
    if tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1; then
      echo "    $service reset"
    else
      echo "    $service: nothing to reset"
    fi
  done
else
  echo "==> Keeping privacy permissions (--keep-permissions)"
fi

echo "==> Unregistering from Launch Services"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
for app in "$ROOT/build/WhizMe.app" "$HOME/Library/Developer/Xcode/DerivedData"/WhizMe-*/Build/Products/*/WhizMe.app; do
  [ -e "$app" ] || continue
  "$LSREGISTER" -u "$app" 2>/dev/null || true
done

if [ "$CLEAN_BUILD" -eq 1 ]; then
  echo "==> Removing build products"
  rm -rf "$ROOT/build"
  rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/WhizMe-*
fi

echo
echo "==> Done. The next launch is a first run."
echo
echo "    Two things this cannot reset, because macOS exposes no per-app switch:"
echo "      * Notifications — System Settings ▸ Notifications ▸ WhizMe, if it is listed."
echo "      * Launch at login — if you ever switched it on, turn it off in WhizMe's"
echo "        Settings before resetting, or it survives as a background item."
echo
if [ "$KEEP_PERMISSIONS" -eq 0 ]; then
  echo "    You will be asked for Accessibility and Screen Recording again on first use."
fi
