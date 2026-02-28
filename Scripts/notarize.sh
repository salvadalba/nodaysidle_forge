#!/bin/bash
# Forge — Build, sign, and notarize for distribution
# Usage: ./Scripts/notarize.sh
#
# Prerequisites:
#   - Developer ID Application certificate in Keychain
#   - App-specific password stored in Keychain as "AC_PASSWORD"
#   - Set DEVELOPER_ID and APPLE_ID environment variables

set -euo pipefail

# Configuration
APP_NAME="Forge"
BUNDLE_ID="com.forge.editor"
SCHEME="Forge"
BUILD_DIR=".build/release"
DMG_NAME="${APP_NAME}.dmg"
STAGING_DIR=".build/dmg-staging"

DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: Your Name (TEAMID)}"
APPLE_ID="${APPLE_ID:-your@email.com}"
TEAM_ID="${TEAM_ID:-YOURTEAMID}"

echo "=== Building ${APP_NAME} for Release ==="

# Step 1: Build release binary
swift build -c release
echo "Build successful"

# Step 2: Verify binary exists
BINARY="${BUILD_DIR}/${APP_NAME}"
if [ ! -f "${BINARY}" ]; then
    echo "ERROR: Binary not found at ${BINARY}"
    exit 1
fi
echo "Binary: ${BINARY}"

# Step 3: Code sign with Developer ID
echo "=== Code Signing ==="
codesign --force --options runtime \
    --sign "${DEVELOPER_ID}" \
    --timestamp \
    --entitlements /dev/null \
    "${BINARY}"

codesign --verify --verbose "${BINARY}"
echo "Code signing verified"

# Step 4: Create DMG
echo "=== Creating DMG ==="
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
cp "${BINARY}" "${STAGING_DIR}/"

# Create a simple DMG
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}"

echo "DMG created: ${BUILD_DIR}/${DMG_NAME}"

# Step 5: Sign the DMG
codesign --force --sign "${DEVELOPER_ID}" \
    --timestamp \
    "${BUILD_DIR}/${DMG_NAME}"

# Step 6: Notarize
echo "=== Notarizing ==="
xcrun notarytool submit "${BUILD_DIR}/${DMG_NAME}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${TEAM_ID}" \
    --password "@keychain:AC_PASSWORD" \
    --wait

echo "=== Stapling Notarization Ticket ==="
xcrun stapler staple "${BUILD_DIR}/${DMG_NAME}"

echo "=== Done ==="
echo "Distribution-ready DMG: ${BUILD_DIR}/${DMG_NAME}"

# Cleanup
rm -rf "${STAGING_DIR}"
