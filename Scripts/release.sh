#!/bin/bash
#
# Builds a release, packages it, and regenerates the Sparkle appcast.
#
# Usage:  ./Scripts/release.sh 0.2.0
#
# Output lands in dist/:
#     WhizMe-<version>.zip   upload to the GitHub release tagged v<version>
#     appcast.xml            copy to the website so it serves at SUFeedURL
#
# The appcast is regenerated from every archive in dist/, not just the new one, so
# older entries survive. Keep dist/ around, or Sparkle users on an old version lose
# the entry describing the hop they need.
#
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: ./Scripts/release.sh <marketing-version>   e.g. 0.2.0" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
SPARKLE_BIN="$ROOT/Vendor/Sparkle/bin"
DOWNLOAD_PREFIX="https://github.com/AtharvaBari/WhizMe/releases/download/v${VERSION}/"

# A release signed ad-hoc would hand every existing user a bundle whose designated
# requirement no longer matches theirs: Sparkle would reject the update, and anyone
# who installed it manually would lose Screen Recording. Never let this fall back.
SIGN_IDENTITY="${WHIZME_SIGN_IDENTITY:-Whiz.me Local Signing}"
if ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "ERROR: signing identity '$SIGN_IDENTITY' not found." >&2
  echo "       Run ./Scripts/setup-signing.sh — a release must never be ad-hoc signed." >&2
  exit 1
fi

echo "==> Building release $VERSION"
# build.sh carries the version; keep them in step rather than patching the plist here,
# so a build straight from build.sh is never a different version than a release.
CURRENT_IN_SCRIPT="$(grep '^MARKETING_VERSION=' "$ROOT/Scripts/build.sh" | cut -d'"' -f2)"
if [ "$CURRENT_IN_SCRIPT" != "$VERSION" ]; then
  echo "ERROR: Scripts/build.sh has MARKETING_VERSION=\"$CURRENT_IN_SCRIPT\", not \"$VERSION\"." >&2
  echo "       Bump it (and CURRENT_PROJECT_VERSION in the Xcode project) first." >&2
  exit 1
fi

"$ROOT/Scripts/build.sh" release

mkdir -p "$DIST"
ARCHIVE="$DIST/WhizMe-${VERSION}.zip"

echo "==> Packaging $ARCHIVE"
rm -f "$ARCHIVE"
# ditto, not `zip`: it is the only archiver that preserves the symlink farm and the
# extended attributes a signed framework needs. A `zip -r` archive of this bundle
# arrives with a broken signature.
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/WhizMe.app" "$ARCHIVE"

echo "==> Verifying the packaged copy still validates"
UNPACK="$(mktemp -d)"
trap 'rm -rf "$UNPACK"' EXIT
ditto -x -k "$ARCHIVE" "$UNPACK"
codesign --verify --deep --strict "$UNPACK/WhizMe.app" \
  && echo "    OK: signature survived packaging."

echo "==> Generating appcast (signs each archive with the EdDSA key in your keychain)"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://github.com/AtharvaBari/WhizMe" \
  -o "$DIST/appcast.xml" \
  "$DIST"

echo "==> Publishing appcast to the repo root"
# Sparkle reads the feed from raw.githubusercontent, which serves whatever is
# committed on the default branch — so the appcast has to live at the repo root and
# be committed, not left in the ignored dist/ directory.
cp "$DIST/appcast.xml" "$ROOT/appcast.xml"

echo
echo "==> Done."
echo "    1. Create GitHub release  v$VERSION  and upload  $(basename "$ARCHIVE")"
echo "    2. Commit and push appcast.xml at the repo root:"
echo "         git add appcast.xml && git commit -m \"Release v$VERSION\" && git push"
echo "    Order matters: publish the archive before the appcast, or a client that"
echo "    reads the feed in between gets a 404 on the download."
