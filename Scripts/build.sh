#!/bin/bash
#
# Builds WhizMe.app without xcodebuild, using only the toolchain in Xcode.app.
#
# Why this exists: `xcodebuild` refuses to start when Xcode's first-launch packages
# are missing (it hard-fails loading the simulator plugin, even for a macOS-only
# project). This script needs none of that, so it also works on a CI box with just
# the Command Line Tools plus an Xcode toolchain.
#
# Usage:  ./Scripts/build.sh [debug|release]     (default: debug)
#
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/WhizMe.app"

BUNDLE_ID="me.whiz.app"
EXECUTABLE="WhizMe"
MARKETING_VERSION="0.1.1"
BUILD_VERSION="2"
DEPLOYMENT_TARGET="14.0"

SDK="$(xcrun --show-sdk-path --sdk macosx)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos${DEPLOYMENT_TARGET}"

SPARKLE_DIR="$ROOT/Vendor/Sparkle"
"$ROOT/Scripts/fetch-sparkle.sh" | sed 's/^/    /'

if [ "$CONFIG" = "release" ]; then
  SWIFT_FLAGS=(-O -whole-module-optimization)
  # A signature with no secure timestamp stops validating the day the certificate
  # expires, which would strand every copy already installed. Debug builds skip it
  # because it costs a network round trip per signed item and they are never shipped.
  TIMESTAMP_FLAG=(--timestamp)
else
  SWIFT_FLAGS=(-Onone -g)
  TIMESTAMP_FLAG=(--timestamp=none)
fi

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

echo "==> Embedding Sparkle.framework"
# -R preserves the Versions/Current symlink farm, which a versioned framework needs
# to stay valid. Headers and module maps are compile-time only; Apple's guidance is
# not to ship them, and leaving them in means signing files no one will ever load.
cp -R "$SPARKLE_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Headers" \
       "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/PrivateHeaders" \
       "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Modules" \
       "$APP/Contents/Frameworks/Sparkle.framework/Headers" \
       "$APP/Contents/Frameworks/Sparkle.framework/PrivateHeaders" \
       "$APP/Contents/Frameworks/Sparkle.framework/Modules"

echo "==> Compiling Swift ($CONFIG, $TARGET)"
# Every framework used (AppKit, SwiftUI, IOKit, Vision, ScreenCaptureKit,
# UserNotifications, Carbon, ServiceManagement, CoreGraphics, ApplicationServices)
# is a system framework with a Clang module, so Swift autolinking resolves them
# from the `import` statements alone — no -framework flags required.
SWIFT_FILES=()
while IFS=  read -r -d $'\0' file; do
  SWIFT_FILES+=("$file")
done < <(find "$ROOT/Core/WhizMe" -name "*.swift" -print0)

# Closed-source Pro sources, when this working copy has them. A Core-only clone
# builds the free app from exactly the same script — the directory simply is not there.
if [ -d "$ROOT/Pro/Sources" ]; then
  while IFS=  read -r -d $'\0' file; do
    SWIFT_FILES+=("$file")
  done < <(find "$ROOT/Pro/Sources" -name "*.swift" -print0)
  echo "    Including $(find "$ROOT/Pro/Sources" -name "*.swift" | wc -l | tr -d " ") Pro source file(s)"
fi

# WHIZME_STRICT=1 turns warnings into errors. .cursorrules says a new warning is a bug;
# CI sets this so that rule is enforced rather than merely stated. Left off locally so a
# work-in-progress build is not blocked by an unused variable.
xcrun swiftc \
  -swift-version 6 \
  -strict-concurrency=complete \
  ${WHIZME_STRICT:+-warnings-as-errors} \
  -target "$TARGET" \
  -sdk "$SDK" \
  -parse-as-library \
  -F "$SPARKLE_DIR" \
  -framework Sparkle \
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
  "${SWIFT_FLAGS[@]}" \
  -o "$APP/Contents/MacOS/$EXECUTABLE" \
  "${SWIFT_FILES[@]}"

echo "==> Compiling asset catalog"
xcrun actool "$ROOT/Core/WhizMe/Assets.xcassets" \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target "$DEPLOYMENT_TARGET" \
  --app-icon AppIcon \
  --output-partial-info-plist "$BUILD_DIR/assets-partial.plist" \
  2>&1 | grep -iE "error" | sed 's/^/    /' || true
if [ ! -f "$APP/Contents/Resources/Assets.car" ]; then
  echo "    ERROR: asset catalog did not compile — Logo and AccentColor will be missing." >&2
  exit 1
fi

echo "==> Writing Info.plist"
sed -e "s|\$(DEVELOPMENT_LANGUAGE)|en|g" \
    -e "s|\$(EXECUTABLE_NAME)|$EXECUTABLE|g" \
    -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$BUNDLE_ID|g" \
    -e "s|\$(PRODUCT_NAME)|$EXECUTABLE|g" \
    -e "s|\$(MARKETING_VERSION)|$MARKETING_VERSION|g" \
    -e "s|\$(CURRENT_PROJECT_VERSION)|$BUILD_VERSION|g" \
    -e "s|\$(MACOSX_DEPLOYMENT_TARGET)|$DEPLOYMENT_TARGET|g" \
    "$ROOT/Core/Config/Info.plist" > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# Prefer a stable certificate. Ad-hoc signing recomputes the designated requirement
# from the binary on every build, so macOS treats each rebuild as a different app and
# silently drops its Screen Recording and Accessibility grants. See Scripts/setup-signing.sh.
SIGN_IDENTITY="${WHIZME_SIGN_IDENTITY:-Whiz.me Local Signing}"
if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  echo "==> Signing as '$SIGN_IDENTITY'"
else
  SIGN_IDENTITY="-"
  echo "==> Signing (ad-hoc)"
  echo "    WARNING: macOS will forget this app's privacy permissions on every rebuild."
  echo "    Run ./Scripts/setup-signing.sh once to fix that."
fi

# Hardened runtime on both configurations, matching the Xcode project. macOS records a
# privacy grant against the exact code identity that asked for it, so a debug build that
# is signed differently from a release build reads as a different app and has to be
# granted separately. Keeping the two identical is what lets one grant cover both.
# Sparkle ships ad-hoc signed (TeamIdentifier=not set) so that integrators re-sign it.
# That re-signing is mandatory here, not cosmetic: under the Hardened Runtime, Library
# Validation refuses to load a dylib whose Team ID differs from the host process, which
# is the same failure the debug-dylib note above describes. Everything inside the bundle
# has to present WhizMe's identity.
#
# Nested code is signed innermost-first. Signing a container seals hashes of everything
# it holds, so any nested bundle signed afterwards invalidates the seal above it.
# Nested Sparkle code gets NO entitlements file — Apple Events access is WhizMe's to
# hold, not the updater's.
echo "==> Signing nested Sparkle code (innermost first)"
SPARKLE_EMBEDDED="$APP/Contents/Frameworks/Sparkle.framework"
for nested in \
  "$SPARKLE_EMBEDDED/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE_EMBEDDED/Versions/B/XPCServices/Installer.xpc" \
  "$SPARKLE_EMBEDDED/Versions/B/Updater.app" \
  "$SPARKLE_EMBEDDED/Versions/B/Autoupdate" \
  "$SPARKLE_EMBEDDED/Versions/B"
do
  [ -e "$nested" ] || continue
  codesign --force --sign "$SIGN_IDENTITY" \
    --options runtime \
    "${TIMESTAMP_FLAG[@]}" \
    "$nested" 2>&1 | sed 's/^/    /'
done

codesign --force --sign "$SIGN_IDENTITY" \
  --entitlements "$ROOT/Core/Config/WhizMe.entitlements" \
  --options runtime \
  "${TIMESTAMP_FLAG[@]}" \
  "$APP" 2>&1 | sed 's/^/    /'

echo "==> Verifying nested code seals"
codesign --verify --deep --strict "$APP" 2>&1 | sed 's/^/    /' \
  && echo "    OK: every nested bundle verifies."

echo "==> Designated requirement (what TCC matches on)"
codesign -d -r- "$APP" 2>&1 | grep designated | sed 's/^/    /'

echo "==> Built $APP"
