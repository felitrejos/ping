#!/usr/bin/env bash
set -euo pipefail

# Release script for direct macOS distribution.
# Supports two signing modes:
# - unsigned (default): no paid Apple Developer Program required
# - developer-id: archive/export path for notarized distribution
#
# Default flow (unsigned):
# 1) Build macOS app (Release)
# 2) Ad-hoc sign app bundle
# 3) Create DMG
#
# Optional notarization is only available in developer-id mode.

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
SIGNING_MODE="${SIGNING_MODE:-unsigned}" # unsigned | developer-id

# developer-id mode variables
ARCHIVE_PATH="${ARCHIVE_PATH:-${BUILD_DIR}/${APP_NAME}.xcarchive}"
EXPORT_METHOD="${EXPORT_METHOD:-developer-id}"
TEAM_ID="${TEAM_ID:-}"

# notarization variables
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

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
  exit 1
fi

if [[ "${SIGNING_MODE}" != "unsigned" && "${SIGNING_MODE}" != "developer-id" ]]; then
  echo "error: SIGNING_MODE must be 'unsigned' or 'developer-id'"
  exit 1
fi

if [[ "${NOTARIZE}" == "1" && "${SIGNING_MODE}" != "developer-id" ]]; then
  echo "error: notarization requires SIGNING_MODE=developer-id"
  exit 1
fi

mkdir -p "${BUILD_DIR}"
rm -rf "${EXPORT_PATH}" "${DMG_PATH}" "${ARCHIVE_PATH}"

if [[ "${SIGNING_MODE}" == "developer-id" ]]; then
  if [[ -z "${TEAM_ID}" ]]; then
    TEAM_ID="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -showBuildSettings 2>/dev/null | awk '/DEVELOPMENT_TEAM = / { print $3; exit }')"
  fi

  if [[ -z "${TEAM_ID}" ]]; then
    echo "error: TEAM_ID is required for developer-id mode"
    exit 1
  fi

  EXPORT_OPTIONS_PLIST="${BUILD_DIR}/ExportOptions.plist"
  cat > "${EXPORT_OPTIONS_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${EXPORT_METHOD}</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
PLIST

  echo "==> Archiving ${SCHEME} (${CONFIGURATION})"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    archive

  echo "==> Exporting app (${EXPORT_METHOD})"
  xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

  APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"
else
  DERIVED_DATA_PATH="${BUILD_DIR}/DerivedData"

  echo "==> Building ${SCHEME} (${CONFIGURATION}) [unsigned mode]"
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

  # Ad-hoc sign so macOS treats bundle as a valid code-signed app package.
  codesign --force --deep --sign - "${APP_PATH}"
fi

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: app not found at ${APP_PATH}"
  exit 1
fi

echo "==> Creating DMG at ${DMG_PATH}"
hdiutil create \
  -volname "${DMG_VOLUME_NAME}" \
  -srcfolder "${APP_PATH}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

if [[ "${NOTARIZE}" == "1" ]]; then
  if [[ -z "${NOTARY_PROFILE}" ]]; then
    echo "error: NOTARIZE=1 requires NOTARY_PROFILE"
    exit 1
  fi

  echo "==> Notarizing DMG"
  xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait

  echo "==> Stapling notarization ticket"
  xcrun stapler staple "${DMG_PATH}"
  xcrun stapler validate "${DMG_PATH}"
fi

echo ""
echo "Release artifact ready: ${DMG_PATH}"
echo "Signing mode: ${SIGNING_MODE}"
if [[ "${NOTARIZE}" == "1" ]]; then
  echo "Notarization: completed"
else
  echo "Notarization: skipped"
fi
