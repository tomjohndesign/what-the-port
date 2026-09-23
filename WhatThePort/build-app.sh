#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="WhatThePort"
APP_DIR=".build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"

swift build -c release

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources"

cp ".build/release/${APP_NAME}" "${CONTENTS_DIR}/MacOS/"
cp "Info.plist" "${CONTENTS_DIR}/"
cp -R "Resources/Fonts" "${CONTENTS_DIR}/Resources/"

# Ad-hoc signature until there's a Developer ID to sign and notarize with.
codesign --force --sign - --timestamp=none "${APP_DIR}"

echo "Built ${APP_DIR}"
echo "Run with: open ${APP_DIR}"
