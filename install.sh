#!/bin/bash
# Builds AIPapers (Release) and installs it to /Applications, replacing
# whatever's there. Run this after making changes to get them onto your Mac.
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="AIPapers.xcodeproj"
SCHEME="AIPapers"
CONFIGURATION="Release"
INSTALL_PATH="/Applications/AIPapers.app"

echo "==> Building $SCHEME ($CONFIGURATION)"
BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIGURATION" -allowProvisioningUpdates build

BUILT_APP="$BUILD_DIR/AIPapers.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "error: build succeeded but $BUILT_APP wasn't found" >&2
  exit 1
fi

echo "==> Installing to $INSTALL_PATH"
pkill -x AIPapers 2>/dev/null || true
sleep 1
rm -rf "$INSTALL_PATH"
ditto "$BUILT_APP" "$INSTALL_PATH"

echo "==> Verifying signature"
codesign --verify --deep --strict "$INSTALL_PATH"

echo "==> Launching"
open "$INSTALL_PATH"

echo "==> Done — installed to $INSTALL_PATH"
