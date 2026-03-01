#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

DEVICE_ID=$(xcrun xctrace list devices 2>&1 | grep -v Simulator | grep -v Offline | grep -v "==" | grep -v "^$" | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
if [ -z "$DEVICE_ID" ]; then
  echo "Error: No connected device found. Plug in your phone and try again."
  exit 1
fi
echo "Found device: $DEVICE_ID"
APP_PATH="$PROJECT_DIR/build/Debug-iphoneos/ShieldBug.app"

echo "Building ShieldBug..."
set -o pipefail
xcodebuild \
  -project "$PROJECT_DIR/ShieldBug.xcodeproj" \
  -target ShieldBug \
  -configuration Debug \
  -sdk iphoneos \
  SUPPORTED_PLATFORMS="iphoneos iphonesimulator" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration 2>&1 \
  | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"

echo "Installing on device $DEVICE_ID..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "Launching app (Ctrl+C to detach)..."
xcrun devicectl device process launch --console --device "$DEVICE_ID" shieldbug.ShieldBug
