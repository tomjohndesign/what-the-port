#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="WhatThePort"
APP_DIR=".build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"

if [[ "${1:-}" != "" && "${1:-}" != "--release" ]]; then
    echo "Usage: $0 [--release]" >&2
    exit 1
fi
if [[ -f update-config.env ]]; then
    source update-config.env
fi
export SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
export SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
export WTP_VERSION="${WTP_VERSION:-}"
export WTP_BUILD="${WTP_BUILD:-}"
export REQUIRE_UPDATES="${1:-}"

# Validate before building, including partial configuration in local builds.
python3 scripts/configure-updates.py Info.plist .build/configured-Info.plist
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
FRAMEWORK="${BIN_DIR}/Sparkle.framework"
if [[ ! -d "${FRAMEWORK}" ]]; then
    echo "Sparkle.framework is missing from ${BIN_DIR}" >&2
    exit 1
fi

rm -rf "${APP_DIR}"
mkdir -p "${CONTENTS_DIR}/MacOS" "${CONTENTS_DIR}/Resources" "${CONTENTS_DIR}/Frameworks"
cp "${BIN_DIR}/${APP_NAME}" "${CONTENTS_DIR}/MacOS/"
cp .build/configured-Info.plist "${CONTENTS_DIR}/Info.plist"
cp -R "Resources/Fonts" "${CONTENTS_DIR}/Resources/"
cp "Resources/AppIcon.icns" "${CONTENTS_DIR}/Resources/"
ditto "${BIN_DIR}/WhatThePort_WhatThePort.bundle" "${CONTENTS_DIR}/Resources/WhatThePort_WhatThePort.bundle"
ditto "${FRAMEWORK}" "${CONTENTS_DIR}/Frameworks/Sparkle.framework"

# Sign from the inside out. Preserve Sparkle's helper entitlements.
IDENTITY="${CODE_SIGN_IDENTITY:--}"
SIGN_OPTIONS=(--force --sign "${IDENTITY}")
if [[ "${IDENTITY}" == "-" ]]; then
    SIGN_OPTIONS+=(--timestamp=none)
else
    SIGN_OPTIONS+=(--options runtime --timestamp)
fi
SPARKLE="${CONTENTS_DIR}/Frameworks/Sparkle.framework/Versions/B"
for component in "${SPARKLE}/XPCServices/Downloader.xpc" \
                 "${SPARKLE}/XPCServices/Installer.xpc" \
                 "${SPARKLE}/Autoupdate" \
                 "${SPARKLE}/Updater.app" \
                 "${CONTENTS_DIR}/Frameworks/Sparkle.framework"; do
    codesign "${SIGN_OPTIONS[@]}" --preserve-metadata=entitlements "${component}"
done
codesign "${SIGN_OPTIONS[@]}" "${APP_DIR}"
codesign --verify --deep --strict "${APP_DIR}"

echo "Built ${APP_DIR}"
echo "Run with: open ${APP_DIR}"
