#!/bin/bash
#
# Build, sign, install, and launch penpal on a physical iPad.
#
# === First-time setup ===
# Fill in DEVICE_ID and SIGN_ID below with your own values.
# (Tip: paste this whole comment block into Claude Code and it can run the
#  commands for you and fill in the placeholders automatically.)
#
#   DEVICE_ID — the UDID of your iPad. Find it with:
#       xcrun devicectl list devices
#     Look for your iPad's "Identifier" column (a UUID-like string).
#
#   SIGN_ID — the SHA-1 fingerprint of your Apple Development signing
#     certificate. List your installed identities with:
#       security find-identity -v -p codesigning
#     Pick the one that says "Apple Development: <your name> (XXXXXXXXXX)" and
#     copy the 40-char hex hash to the left of it.
#
# Free Apple ID developer accounts work — just open the project once in Xcode,
# select your team in Signing & Capabilities, and Xcode will create the cert.
# ============================================================================
set -e

DEVICE_ID="YOUR_DEVICE_UDID_HERE"          # e.g. 00008130-001A23B4567C001D
BUNDLE_ID="com.magicnotebook.penpal"
SCHEME="penpal"
DERIVED="$(cd "$(dirname "$0")" && pwd)/build-device"
APP="$DERIVED/Build/Products/Debug-iphoneos/penpal.app"
XCENT="$DERIVED/Build/Intermediates.noindex/penpal.build/Debug-iphoneos/penpal.build/penpal.app.xcent"
SIGN_ID="YOUR_SIGNING_CERT_SHA1_HERE"      # e.g. ABCDEF1234567890ABCDEF1234567890ABCDEF12

if [ "$DEVICE_ID" = "YOUR_DEVICE_UDID_HERE" ] || [ "$SIGN_ID" = "YOUR_SIGNING_CERT_SHA1_HERE" ]; then
  echo "ERROR: edit this script and fill in DEVICE_ID and SIGN_ID first."
  echo "       See the comment block at the top of $0 for instructions."
  exit 1
fi

echo "Building..."
xcodebuild -scheme "$SCHEME" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED|CodeSign failed" || true

# Strip iCloud xattrs and re-sign (needed when project is in iCloud Drive)
if [ -d "$APP" ]; then
  echo "Stripping xattrs..."
  xattr -cr "$APP"
  echo "Signing..."
  /usr/bin/codesign --force --sign "$SIGN_ID" \
    --entitlements "$XCENT" \
    --timestamp=none --generate-entitlement-der "$APP"
  echo "Installing..."
  xcrun devicectl device install app --device "$DEVICE_ID" "$APP"
  echo "Launching..."
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"
  echo "Done."
else
  echo "Build failed — no .app found."
  exit 1
fi
