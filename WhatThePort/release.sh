#!/bin/bash
# Prepare signed update artifacts locally. Does not publish or deploy anything.
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -ne 2 || -z "${1:-}" || -z "${2:-}" ]]; then
    echo "Usage: $0 <version> <build-number>" >&2
    exit 1
fi
if [[ -f update-config.env ]]; then
    source update-config.env
fi
export WTP_VERSION="$1" WTP_BUILD="$2"
export SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
export SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
export CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
export REQUIRE_UPDATES=--release
python3 scripts/configure-updates.py Info.plist .build/configured-Info.plist

UPDATES=".build/updates"
ARCHIVE="${UPDATES}/WhatThePort-${WTP_BUILD}.zip"
if [[ -e "${ARCHIVE}" ]]; then
    echo "${ARCHIVE} already exists. Use a new, increasing build number for each release." >&2
    exit 1
fi
./build-app.sh --release
TOOLS=".build/artifacts/sparkle/Sparkle/bin"
APP=".build/WhatThePort.app"
if [[ "$("${TOOLS}/generate_keys" -p)" != "${SPARKLE_PUBLIC_KEY}" ]]; then
    echo "SPARKLE_PUBLIC_KEY does not match the signing key in your Keychain." >&2
    exit 1
fi

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    if [[ "${CODE_SIGN_IDENTITY}" == "-" ]]; then
        echo "Notarization requires CODE_SIGN_IDENTITY to be a Developer ID certificate." >&2
        exit 1
    fi
    ditto -c -k --sequesterRsrc --keepParent "${APP}" .build/notarize.zip
    xcrun notarytool submit .build/notarize.zip --keychain-profile "${NOTARYTOOL_PROFILE}" --wait
    xcrun stapler staple "${APP}"
    xcrun stapler validate "${APP}"
fi

STAGING="$(mktemp -d .build/update-staging.XXXXXX)"
trap 'rm -rf "${STAGING}"' EXIT
mkdir -p "${STAGING}/updates"
if [[ -d "${UPDATES}" ]]; then
    ditto "${UPDATES}" "${STAGING}/updates"
fi
STAGED_ARCHIVE="${STAGING}/updates/WhatThePort-${WTP_BUILD}.zip"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${STAGED_ARCHIVE}"
SIGNATURE="$("${TOOLS}/sign_update" -p "${STAGED_ARCHIVE}")"
"${TOOLS}/sign_update" --verify "${STAGED_ARCHIVE}" "${SIGNATURE}"
"${TOOLS}/generate_appcast" --download-url-prefix "${SPARKLE_FEED_URL%/*}/" "${STAGING}/updates"
# Only expose artifacts after signing and feed generation both succeed.
ditto "${STAGING}/updates" "${UPDATES}"
cp "${ARCHIVE}" .build/WhatThePort.zip

echo "Prepared ${ARCHIVE}, ${UPDATES}/appcast.xml and .build/WhatThePort.zip"
echo "Publish the updates directory at ${SPARKLE_FEED_URL%/*}/ and replace the website download with .build/WhatThePort.zip."
