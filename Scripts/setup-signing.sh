#!/bin/bash
#
# Gives WhizMe a stable local code-signing identity. Run ONCE per machine.
# Safe to re-run: it repairs whatever step is missing and changes nothing else.
#
# WHY THIS IS NECESSARY
#
# macOS ties privacy grants (Screen Recording, Accessibility) to an app's *designated
# requirement*, not to its path or bundle ID. An ad-hoc signed app — `codesign -s -`,
# which is what Xcode falls back to when no certificate exists — has this requirement:
#
#     designated => cdhash H"9e246fd8359db746bc00dc853999a99347abe101"
#
# That hash is computed from the binary, so it changes on every single build. TCC
# therefore sees each rebuild as a brand-new app: the grant you gave five minutes ago
# no longer matches, the app is denied, and it asks again. System Settings still shows
# the toggle ON, because that row belongs to the *previous* build — which is exactly
# why it looks like macOS is ignoring a permission you already granted.
#
# Signing with a real certificate — even a self-signed one — changes it to:
#
#     designated => identifier "me.whiz.app" and certificate root = H"29f0fd40..."
#
# That hash belongs to the certificate, not the binary, so it survives every rebuild
# and the grant sticks.
#
# Prefer an Apple Development certificate? Sign into Xcode (Settings → Accounts) with
# any free Apple ID and set CODE_SIGN_STYLE back to Automatic. This script exists so
# that neither an Apple ID nor an admin password is required.
#
set -euo pipefail

IDENTITY_NAME="Whiz.me Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

has_cert()    { security find-certificate -c "$IDENTITY_NAME" >/dev/null 2>&1; }
is_trusted()  { security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; }

if [ "${1:-}" = "--force" ] && has_cert; then
  echo "==> --force: removing the existing identity"
  echo "    (this resets your TCC grants one final time — you will re-grant once)"
  security delete-identity -c "$IDENTITY_NAME" "$KEYCHAIN" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------- create ----
if has_cert; then
  echo "==> Certificate '$IDENTITY_NAME' already in your login keychain"
else
  echo "==> Generating a self-signed code-signing certificate (10 year validity)"
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK_DIR/key.pem" \
    -out "$WORK_DIR/cert.pem" \
    -subj "/CN=$IDENTITY_NAME/O=Whiz.me/C=US" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    >/dev/null 2>&1

  openssl pkcs12 -export \
    -out "$WORK_DIR/identity.p12" \
    -inkey "$WORK_DIR/key.pem" \
    -in "$WORK_DIR/cert.pem" \
    -passout pass:whizme \
    >/dev/null 2>&1

  echo "==> Importing into your login keychain"
  # -T pre-authorises codesign to use the private key, so signing never puts up a
  # "wants to use your confidential information" dialog mid-build.
  security import "$WORK_DIR/identity.p12" \
    -k "$KEYCHAIN" \
    -P whizme \
    -T /usr/bin/codesign \
    -T /usr/bin/productsign \
    >/dev/null
  echo "    Created."
fi

# ----------------------------------------------------------------- trust ----
# `codesign` (and therefore ./Scripts/build.sh) works without this. Xcode's build
# system only offers identities that are *trusted* for code signing, so the Run
# button needs it. macOS asks for your login password here — that prompt is this step.
if is_trusted; then
  echo "==> Already trusted for code signing"
else
  echo "==> Marking the certificate as trusted for code signing"
  echo "    macOS will ask for your login password now."
  security find-certificate -c "$IDENTITY_NAME" -p > "$WORK_DIR/existing.pem"
  if security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK_DIR/existing.pem" 2>/dev/null \
     && is_trusted; then
    echo "    Trusted."
  else
    echo
    echo "    Could not set trust automatically (cancelled, or macOS declined)."
    echo "    ./Scripts/build.sh works regardless. For Xcode's Run button, do it by hand:"
    echo "      Keychain Access → login → Certificates → '$IDENTITY_NAME'"
    echo "      → Get Info → Trust → 'When using this certificate: Always Trust' → close → save"
    echo
  fi
fi

# ------------------------------------------------------------ stale TCC ----
echo
echo "==> Clearing permission entries left behind by earlier ad-hoc builds"
# Those rows can never match the new identity, and a stale entry keeps the app in the
# denied state even after you toggle it on.
tccutil reset ScreenCapture me.whiz.app >/dev/null 2>&1 && echo "    Screen Recording reset" || echo "    Screen Recording: nothing to reset"
tccutil reset Accessibility me.whiz.app >/dev/null 2>&1 && echo "    Accessibility reset"   || echo "    Accessibility: nothing to reset"

echo
echo "==> Done. Rebuild, launch, and grant the permissions once — they will stick from now on."
echo "    Verify any time with:  codesign -d -r- build/WhizMe.app"
