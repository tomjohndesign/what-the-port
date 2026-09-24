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

# Notarize with a stored notarytool profile, or with an App Store Connect API key (used in CI).
NOTARY_AUTH=()
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
    NOTARY_AUTH=(--keychain-profile "${NOTARYTOOL_PROFILE}")
elif [[ -n "${NOTARY_API_KEY_PATH:-}" ]]; then
    if [[ -z "${NOTARY_API_KEY_ID:-}" || -z "${NOTARY_API_ISSUER_ID:-}" ]]; then
        echo "NOTARY_API_KEY_PATH also requires NOTARY_API_KEY_ID and NOTARY_API_ISSUER_ID." >&2
        exit 1
    fi
    NOTARY_AUTH=(--key "${NOTARY_API_KEY_PATH}" --key-id "${NOTARY_API_KEY_ID}" --issuer "${NOTARY_API_ISSUER_ID}")
fi
if [[ ${#NOTARY_AUTH[@]} -gt 0 && "${CODE_SIGN_IDENTITY}" == "-" ]]; then
    echo "Notarization requires CODE_SIGN_IDENTITY to be a Developer ID certificate." >&2
    exit 1
fi
if [[ ${#NOTARY_AUTH[@]} -eq 0 && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    echo "warning: signing without notarization. Gatekeeper will still block first-time downloads." >&2
fi

# Sparkle reads its private key from the login Keychain unless a key file is given (used in CI).
SPARKLE_KEY=()
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    SPARKLE_KEY=(--ed-key-file "${SPARKLE_PRIVATE_KEY_FILE}")
fi

UPDATES=".build/updates"
ARCHIVE="${UPDATES}/WhatThePort-${WTP_BUILD}.zip"
if [[ -e "${ARCHIVE}" ]]; then
    echo "${ARCHIVE} already exists. Use a new, increasing build number for each release." >&2
    exit 1
fi
./build-app.sh --release
TOOLS=".build/artifacts/sparkle/Sparkle/bin"
APP=".build/WhatThePort.app"

if [[ ${#NOTARY_AUTH[@]} -gt 0 ]]; then
    ditto -c -k --sequesterRsrc --keepParent "${APP}" .build/notarize.zip
    SUBMISSION="$(xcrun notarytool submit .build/notarize.zip "${NOTARY_AUTH[@]}" --wait --output-format json)"
    echo "${SUBMISSION}"
    read -r SUBMISSION_ID STATUS < <(python3 -c 'import json, sys; s = json.load(sys.stdin); print(s["id"], s["status"])' <<< "${SUBMISSION}")
    if [[ "${STATUS}" != "Accepted" ]]; then
        xcrun notarytool log "${SUBMISSION_ID}" "${NOTARY_AUTH[@]}" >&2 || true
        echo "Notarization finished with status ${STATUS}." >&2
        exit 1
    fi
    xcrun stapler staple "${APP}"
    xcrun stapler validate "${APP}"
    spctl --assess --type execute --verbose=2 "${APP}"
fi

STAGING="$(mktemp -d .build/update-staging.XXXXXX)"
trap 'rm -rf "${STAGING}"' EXIT
mkdir -p "${STAGING}/updates"
if [[ -d "${UPDATES}" ]]; then
    ditto "${UPDATES}" "${STAGING}/updates"
fi
STAGED_ARCHIVE="${STAGING}/updates/WhatThePort-${WTP_BUILD}.zip"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${STAGED_ARCHIVE}"
SIGNATURE="$("${TOOLS}/sign_update" ${SPARKLE_KEY[@]+"${SPARKLE_KEY[@]}"} -p "${STAGED_ARCHIVE}")"
# Check against the key embedded in the app, not just the one that signed.
swift scripts/verify-update-signature.swift "${SPARKLE_PUBLIC_KEY}" "${STAGED_ARCHIVE}" "${SIGNATURE}"
"${TOOLS}/generate_appcast" ${SPARKLE_KEY[@]+"${SPARKLE_KEY[@]}"} --download-url-prefix "${SPARKLE_FEED_URL%/*}/" "${STAGING}/updates"
# Only expose artifacts after signing and feed generation both succeed.
ditto "${STAGING}/updates" "${UPDATES}"
cp "${ARCHIVE}" .build/WhatThePort.zip

echo "Prepared ${ARCHIVE}, ${UPDATES}/appcast.xml and .build/WhatThePort.zip"
echo "Publish the updates directory at ${SPARKLE_FEED_URL%/*}/ and replace the website download with .build/WhatThePort.zip."
