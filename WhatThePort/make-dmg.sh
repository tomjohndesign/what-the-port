#!/bin/bash
# Package the app as the website's disk image: the app beside an Applications
# shortcut on the background in dmg/. Signs the image when CODE_SIGN_IDENTITY
# is a real identity; release.sh notarizes it.
set -euo pipefail
cd "$(dirname "$0")"

APP="${1:-.build/WhatThePort.app}"
DMG="${2:-.build/WhatThePort.dmg}"
if [[ ! -d "${APP}" ]]; then
    echo "Usage: $0 [app] [output.dmg] (build the app with ./build-app.sh first)" >&2
    exit 1
fi

# dmgbuild writes the Finder layout (.DS_Store) directly, so no Finder
# scripting or GUI session is needed.
VENV=".build/dmgbuild"
if [[ ! -x "${VENV}/bin/dmgbuild" ]]; then
    python3 -m venv "${VENV}"
    "${VENV}/bin/pip" install --quiet --disable-pip-version-check dmgbuild==1.6.7
fi

rm -f "${DMG}"
"${VENV}/bin/dmgbuild" -s dmg/settings.py -D app="${APP}" WhatThePort "${DMG}"

IDENTITY="${CODE_SIGN_IDENTITY:--}"
if [[ "${IDENTITY}" != "-" ]]; then
    codesign --force --sign "${IDENTITY}" --timestamp "${DMG}"
    codesign --verify --strict "${DMG}"
fi
hdiutil verify -quiet "${DMG}"
echo "Built ${DMG}"
