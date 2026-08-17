#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="RestPilot"
INFO_PLIST="${ROOT}/Resources/Info.plist"
INFO_VERSION=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' \
  "${INFO_PLIST}")
REQUESTED_VERSION="${1:-${INFO_VERSION}}"
VERSION="${REQUESTED_VERSION#v}"

if [[ "${VERSION}" != "${INFO_VERSION}" ]]; then
  print -u2 \
    "Requested version ${VERSION} does not match Info.plist ${INFO_VERSION}"
  exit 1
fi

RELEASE_DIR="${ROOT}/outputs/release/v${VERSION}"
ARCHIVE_PREFIX="${APP_NAME}-v${VERSION}-macos-universal"
ZIP_PATH="${RELEASE_DIR}/${ARCHIVE_PREFIX}-app.zip"
DMG_PATH="${RELEASE_DIR}/${ARCHIVE_PREFIX}.dmg"
CHECKSUM_PATH="${RELEASE_DIR}/SHA256SUMS.txt"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/restpilot-release.XXXXXX")
trap 'rm -rf "${STAGING}"' EXIT

cd "${ROOT}"
rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

swift build -c release --arch arm64
swift build -c release --arch x86_64

ARM_BINARY="${ROOT}/.build/arm64-apple-macosx/release/${APP_NAME}"
X86_BINARY="${ROOT}/.build/x86_64-apple-macosx/release/${APP_NAME}"
UNIVERSAL_BINARY="${STAGING}/${APP_NAME}"
lipo -create \
  "${ARM_BINARY}" \
  "${X86_BINARY}" \
  -output "${UNIVERSAL_BINARY}"

ARCHITECTURES=$(lipo -archs "${UNIVERSAL_BINARY}")
if [[ " ${ARCHITECTURES} " != *" arm64 "* || \
      " ${ARCHITECTURES} " != *" x86_64 "* ]]; then
  print -u2 "Universal binary is missing an architecture: ${ARCHITECTURES}"
  exit 1
fi

APP_PATH="${STAGING}/${APP_NAME}.app"
"${ROOT}/scripts/assemble-app.sh" "${UNIVERSAL_BINARY}" "${APP_PATH}"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

DMG_ROOT="${STAGING}/dmg"
mkdir -p "${DMG_ROOT}"
ditto "${APP_PATH}" "${DMG_ROOT}/${APP_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" >/dev/null

unzip -tq "${ZIP_PATH}"
hdiutil verify "${DMG_PATH}" >/dev/null

(
  cd "${RELEASE_DIR}"
  shasum -a 256 \
    "${ZIP_PATH:t}" \
    "${DMG_PATH:t}" > "${CHECKSUM_PATH:t}"
)

print "Packaged release assets in ${RELEASE_DIR}"
ls -lh "${ZIP_PATH}" "${DMG_PATH}" "${CHECKSUM_PATH}"
