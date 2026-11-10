#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
RESOURCES="${ROOT}/Resources"

swift "${ROOT}/scripts/render-app-icon.swift" \
  "${RESOURCES}/AppIconArtwork.png" \
  "${RESOURCES}"
iconutil -c icns "${RESOURCES}/AppIcon.iconset" -o "${RESOURCES}/AppIcon.icns"
print "Built ${RESOURCES}/AppIcon.icns"
