#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Building Notch..."
swift build -c release

APP_DIR="dist/Notch.app/Contents"
rm -rf dist
mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources"

cp .build/release/Notch "$APP_DIR/MacOS/Notch"
cp Info.plist "$APP_DIR/Info.plist"

# Ad-hoc sign so Gatekeeper will at least launch a local build.
codesign --force --deep --sign - "dist/Notch.app" >/dev/null 2>&1 || true

ditto -c -k --keepParent "dist/Notch.app" "dist/Notch.zip"

echo ""
echo "Built dist/Notch.app"
echo "Share dist/Notch.zip — unzip, then double-click Notch.app"
echo "Or run locally:  open dist/Notch.app"
