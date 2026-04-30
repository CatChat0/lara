#!/bin/bash
set -euo pipefail

rm -rf build/
mkdir -p build

echo "Build Started!"
echo

# Run xcodebuild, tee raw output to log, pipe through xcpretty for readability
set +e
xcodebuild \
  -project lara.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64e \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="Config/lara.entitlements" \
  archive \
  -archivePath "$PWD/build/lara.xcarchive" 2>&1 \
  | tee build/xcodebuild.log \
  | xcpretty

BUILD_EXIT=${PIPESTATUS[0]}
set -e

if [ $BUILD_EXIT -ne 0 ]; then
  echo ""
  echo "===== BUILD FAILED — FULL ERROR OUTPUT ====="
  grep -E "error:|undefined|duplicate|linker|fatal" build/xcodebuild.log || true
  echo "===== END ERROR OUTPUT ====="
  echo ""
  echo "Full log saved to build/xcodebuild.log"
  exit $BUILD_EXIT
fi

APP_PATH="$PWD/build/lara.xcarchive/Products/Applications/lara.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Missing app at $APP_PATH"
  exit 1
fi
rm -rf "$PWD/build/Payload"
mkdir -p "$PWD/build/Payload"
cp -R "$APP_PATH" "$PWD/build/Payload/"
plutil -replace UIFileSharingEnabled -bool YES "$PWD/build/Payload/lara.app/Info.plist"
if ! command -v ldid >/dev/null 2>&1; then
  echo "ERROR: ldid not installed. Install with: brew install ldid" >&2
  exit 1
fi
ldid -SConfig/lara.entitlements "$PWD/build/Payload/lara.app/lara"
(cd "$PWD/build" && /usr/bin/zip -qry lara.ipa Payload)

echo
echo "Build Successful!"
echo "IPA at: build/lara.ipa"
exit 0
