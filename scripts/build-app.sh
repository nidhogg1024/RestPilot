#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="RestPilot"
OUTPUT="${ROOT}/outputs/${APP_NAME}.app"

cd "${ROOT}"
swift build -c release
"${ROOT}/scripts/assemble-app.sh" \
  "${ROOT}/.build/release/${APP_NAME}" \
  "${OUTPUT}"
