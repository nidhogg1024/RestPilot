#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="RestPilot"
BINARY="${1:?Usage: assemble-app.sh <binary> <output.app>}"
OUTPUT="${2:?Usage: assemble-app.sh <binary> <output.app>}"

if [[ ! -f "${BINARY}" ]]; then
  print -u2 "Missing executable: ${BINARY}"
  exit 1
fi

rm -rf "${OUTPUT}"
mkdir -p "${OUTPUT}/Contents/MacOS" "${OUTPUT}/Contents/Resources"
cp "${BINARY}" "${OUTPUT}/Contents/MacOS/${APP_NAME}"
chmod +x "${OUTPUT}/Contents/MacOS/${APP_NAME}"
cp "${ROOT}/Resources/Info.plist" "${OUTPUT}/Contents/Info.plist"
cp "${ROOT}/Resources/AppIcon.icns" "${OUTPUT}/Contents/Resources/AppIcon.icns"
cp -R "${ROOT}/Resources/Backgrounds" "${OUTPUT}/Contents/Resources/Backgrounds"
cp -R \
  "${ROOT}/Resources/BackgroundThumbnails" \
  "${OUTPUT}/Contents/Resources/BackgroundThumbnails"

# An ad-hoc signature seals the complete bundle for integrity. It does not use
# a Developer ID certificate and does not notarize the app with Apple.
codesign --force --deep --sign - "${OUTPUT}"
codesign --verify --deep --strict --verbose=2 "${OUTPUT}"

print "Built ${OUTPUT}"
