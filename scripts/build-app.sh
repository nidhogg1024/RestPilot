#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="RestPilot"
OUTPUT="${ROOT}/outputs/${APP_NAME}.app"

cd "${ROOT}"
swift build -c release

rm -rf "${OUTPUT}"
mkdir -p "${OUTPUT}/Contents/MacOS" "${OUTPUT}/Contents/Resources"
cp ".build/release/${APP_NAME}" "${OUTPUT}/Contents/MacOS/${APP_NAME}"
cp "${ROOT}/Resources/Info.plist" "${OUTPUT}/Contents/Info.plist"
cp "${ROOT}/Resources/AppIcon.icns" "${OUTPUT}/Contents/Resources/AppIcon.icns"
cp -R "${ROOT}/Resources/Backgrounds" "${OUTPUT}/Contents/Resources/Backgrounds"
cp -R "${ROOT}/Resources/BackgroundThumbnails" "${OUTPUT}/Contents/Resources/BackgroundThumbnails"

echo "Built ${OUTPUT}"
