#!/bin/bash
set -euo pipefail

rm -rf build/
mkdir -p build

echo "Build Started!"
echo

xcodebuild \
  -project EUEnabler.xcodeproj \
  -scheme EUEnabler \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64e \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="Config/EUEnabler.entitlements" \
  archive \
  -archivePath "$PWD/build/EUEnabler.xcarchive" 2>&1 | xcpretty

APP_PATH="$PWD/build/EUEnabler.xcarchive/Products/Applications/EUEnabler.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Missing app at $APP_PATH"
  exit 1
fi
rm -rf "$PWD/build/Payload"
mkdir -p "$PWD/build/Payload"
cp -R "$APP_PATH" "$PWD/build/Payload/"

plutil -replace UIFileSharingEnabled -bool YES "$PWD/build/Payload/EUEnabler.app/Info.plist"

if ! command -v ldid >/dev/null 2>&1; then
  echo "ERROR: ldid not installed. Install with: brew install ldid" >&2
  exit 1
fi
ldid -SConfig/EUEnabler.entitlements "$PWD/build/Payload/EUEnabler.app/EUEnabler"
(cd "$PWD/build" && /usr/bin/zip -qry EUEnabler.ipa Payload)

echo
echo "build successful!"
echo "ipa at: build/EUEnabler.ipa"
exit 0
