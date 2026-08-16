#!/bin/bash
#
# Downloads the pinned Sparkle release into Vendor/ and verifies its checksum.
#
# Sparkle is the one third-party dependency in this project (see .cursorrules). It is
# not committed: a 3 MB binary in git history is worse than a pinned, checksummed
# fetch, and the checksum is what makes the fetch trustworthy rather than "whatever
# GitHub served today".
#
# Usage:  ./Scripts/fetch-sparkle.sh          (no-op if already present and correct)
#         ./Scripts/fetch-sparkle.sh --force  (re-download)
#
set -euo pipefail

SPARKLE_VERSION="2.9.5"
SPARKLE_SHA256="015336b601493e05c237964954bff6191370003d94edefe663724c88840d73cc"
SPARKLE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Vendor/Sparkle"
STAMP="$VENDOR/.version"

if [ "${1:-}" = "--force" ]; then
  rm -rf "$VENDOR"
fi

if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$SPARKLE_VERSION" ] && [ -d "$VENDOR/Sparkle.framework" ]; then
  echo "==> Sparkle $SPARKLE_VERSION already vendored"
  exit 0
fi

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> Downloading Sparkle $SPARKLE_VERSION"
curl -fsSL -o "$WORK_DIR/sparkle.tar.xz" "$SPARKLE_URL"

echo "==> Verifying checksum"
ACTUAL="$(shasum -a 256 "$WORK_DIR/sparkle.tar.xz" | awk '{print $1}')"
if [ "$ACTUAL" != "$SPARKLE_SHA256" ]; then
  echo "    ERROR: checksum mismatch — refusing to use this download." >&2
  echo "      expected: $SPARKLE_SHA256" >&2
  echo "      actual:   $ACTUAL" >&2
  echo "    Either the pinned version was re-tagged upstream, or the download was" >&2
  echo "    tampered with. Do not 'fix' this by pasting in the new hash without" >&2
  echo "    checking https://github.com/sparkle-project/Sparkle/releases first." >&2
  exit 1
fi

echo "==> Extracting"
mkdir -p "$WORK_DIR/x"
tar -xJf "$WORK_DIR/sparkle.tar.xz" -C "$WORK_DIR/x"

rm -rf "$VENDOR"
mkdir -p "$VENDOR"
cp -R "$WORK_DIR/x/Sparkle.framework" "$VENDOR/"
cp -R "$WORK_DIR/x/bin" "$VENDOR/"
cp "$WORK_DIR/x/LICENSE" "$VENDOR/LICENSE"
echo "$SPARKLE_VERSION" > "$STAMP"

echo "==> Vendored to Vendor/Sparkle ($(du -sh "$VENDOR" | awk '{print $1}'))"
