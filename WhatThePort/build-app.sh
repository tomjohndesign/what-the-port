#!/bin/bash
set -e

# Build the executable
swift build -c release

# Create the .app bundle structure
APP_NAME="WhatThePort"
APP_DIR=".build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"

# Copy the executable
cp ".build/release/${APP_NAME}" "${MACOS_DIR}/"

# Copy Info.plist
cp "Info.plist" "${CONTENTS_DIR}/"

echo "Built ${APP_DIR}"
echo "Run with: open ${APP_DIR}"
