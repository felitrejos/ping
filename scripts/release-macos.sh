#!/usr/bin/env bash
set -euo pipefail

# Build an unsigned macOS DMG for direct distribution.
#
# This script is intentionally scoped to the "no paid Apple Developer Program"
# path: it produces an ad-hoc signed .app bundled into a .dmg. Users will see
# Gatekeeper warnings on first launch (right-click > Open, or `xattr -dr
# com.apple.quarantine Ping.app`). That is the cost of not paying Apple.
#
# If a Developer ID certificate and notarization ever become available,
# signing + notarization should be layered on top via a separate workflow
# (or by editing this script) rather than complicating the happy path here.
#
# Flow:
# 1) Build macOS app (Release) with code signing disabled
# 2) Ad-hoc sign the app bundle so macOS recognises it as a valid package
# 3) Create a UDZO DMG containing the app

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PROJECT="${PROJECT:-Ping.xcodeproj}"
SCHEME="${SCHEME:-Ping macOS}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-Ping}"
BUILD_DIR="${BUILD_DIR:-build/release}"
EXPORT_PATH="${EXPORT_PATH:-${BUILD_DIR}/export}"
DMG_PATH="${DMG_PATH:-${BUILD_DIR}/${APP_NAME}.dmg}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-${APP_NAME}}"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild not found"
  exit 1
fi

if ! command -v hdiutil >/dev/null 2>&1; then
  echo "error: hdiutil not found"
  exit 1
fi

if [[ ! -d "${PROJECT}" && ! -f "${PROJECT}" ]]; then
  echo "error: project not found at ${PROJECT}"
  echo "hint: run 'xcodegen generate' first"
  exit 1
fi

mkdir -p "${BUILD_DIR}"
rm -rf "${EXPORT_PATH}" "${DMG_PATH}"

DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"

echo "==> Building ${SCHEME} (${CONFIGURATION}) [unsigned]"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build

BUILT_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [[ ! -d "${BUILT_APP_PATH}" ]]; then
  echo "error: built app not found at ${BUILT_APP_PATH}"
  exit 1
fi

mkdir -p "${EXPORT_PATH}"
cp -R "${BUILT_APP_PATH}" "${EXPORT_PATH}/${APP_NAME}.app"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"

echo "==> Ad-hoc signing ${APP_PATH}"
codesign --force --deep --sign - "${APP_PATH}"

echo "==> Creating DMG at ${DMG_PATH}"
hdiutil create \
  -volname "${DMG_VOLUME_NAME}" \
  -srcfolder "${APP_PATH}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo ""
echo "Release artifact ready: ${DMG_PATH}"
echo "Note: unsigned build. Users may need to right-click > Open on first launch,"
echo "or run: xattr -dr com.apple.quarantine \"${APP_NAME}.app\""
