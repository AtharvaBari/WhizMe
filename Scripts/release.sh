#!/bin/bash
#
# Builds a release, packages it, and regenerates the Sparkle appcast.
#
# Usage:  ./Scripts/release.sh 0.2.0
#
# Output lands in dist/:
#     WhizMe-<version>.dmg   upload to the GitHub release tagged v<version>
#     appcast.xml            commit at the repo root; Sparkle reads it from raw.githubusercontent
#
# One .dmg serves both jobs: the file a new user opens, and the file Sparkle downloads
# to update an existing install.
#
# The appcast is regenerated from every archive in dist/, not just the new one. Sparkle
# always offers the newest item a client qualifies for, so older entries matter only
# when a newer release raises the minimum macOS version and an older one is still the
# right answer for someone. Each entry is rewritten below to point at its own tag.
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
ARCHIVE="$DIST/WhizMe-v${VERSION}.dmg"

# One artifact, used for both jobs: the download a new user opens, and the file
# Sparkle fetches to update an existing install. Shipping a separate .zip for updates
# means two uploads per release and two chances to mismatch the appcast — and when
# they do mismatch, updates fail silently for everyone.
echo "==> Packaging $ARCHIVE"
rm -f "$ARCHIVE"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE" "${UNPACK:-}"; hdiutil detach "$MOUNT" -quiet 2>/dev/null || true' EXIT

# The .app sits at the volume root — Sparkle looks for it there.
cp -R "$ROOT/build/WhizMe.app" "$STAGE/WhizMe.app"

# No license agreement on this image, ever: Sparkle cannot mount a DMG that puts up
# one, so adding it would break every update.
if command -v create-dmg >/dev/null 2>&1; then
  echo "    Using create-dmg to style the DMG background"
  create-dmg \
    --volname "WhizMe" \
    --background "$ROOT/../Brand/bg.png" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 96 \
    --icon "WhizMe.app" 150 200 \
    --hide-extension "WhizMe.app" \
    --app-drop-link 450 200 \
    --no-internet-enable \
    "$ARCHIVE" \
    "$STAGE" >/dev/null 2>&1
else
  echo "    create-dmg not found, falling back to basic hdiutil (no background)"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create \
    -volname "WhizMe" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$ARCHIVE" >/dev/null
fi

echo "==> Verifying the packaged copy still validates"
MOUNT="$(mktemp -d)"
hdiutil attach "$ARCHIVE" -mountpoint "$MOUNT" -nobrowse -quiet
codesign --verify --deep --strict "$MOUNT/WhizMe.app" \
  && echo "    OK: signature survived packaging."
hdiutil detach "$MOUNT" -quiet
MOUNT=""

echo "==> Cleaning up older archives (keeping only the 2 most recent)"
(
  cd "$DIST"
  count=$(ls -1d WhizMe*.dmg 2>/dev/null | wc -l)
  if [ "$count" -gt 2 ]; then
    ls -t WhizMe*.dmg | tail -n +3 | xargs rm -f
  fi
)

echo "==> Generating appcast (signs each archive with the EdDSA key in your keychain)"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://github.com/AtharvaBari/WhizMe" \
  -o "$DIST/appcast.xml" \
  "$DIST"

echo "==> Correcting per-entry download URLs"
# generate_appcast applies ONE --download-url-prefix to every archive it finds, but
# GitHub stores each release's assets under its own tag. So any entry older than the
# version being released comes out pointing at the NEW tag, where its file does not
# exist — a silent 404 for anyone that entry was meant to serve.
#
# Rewrite each enclosure to the tag matching its own version.
python3 - "$DIST/appcast.xml" <<'PY'
import re, sys

path = sys.argv[1]
xml = open(path).read()

def fix(match):
    item = match.group(0)
    version = re.search(r"<sparkle:shortVersionString>([^<]+)<", item)
    if not version:
        return item
    tag = "v" + version.group(1)
    return re.sub(
        r"(releases/download/)v[^/]+/",
        lambda m: m.group(1) + tag + "/",
        item,
    )

xml = re.sub(r"<item>.*?</item>", fix, xml, flags=re.DOTALL)
open(path, "w").write(xml)

for url in re.findall(r'url="([^"]+)"', xml):
    print("   ", url)
PY

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
echo
echo "    Order matters: upload the .dmg BEFORE pushing the appcast. A client that"
echo "    reads the feed in between will 404 on the download."
