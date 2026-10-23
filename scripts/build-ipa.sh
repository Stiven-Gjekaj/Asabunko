#!/bin/sh
# Builds an unsigned Asabunko.ipa in the folder build/.
# A sideload tool, such as AltStore, SideStore, Sideloadly, or TrollStore, signs it.
set -eu

cd "$(dirname "$0")/.."
xcodegen --quiet
xcodebuild \
  -project Asabunko.xcodeproj \
  -scheme Asabunko \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/derived \
  -quiet \
  build

rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R build/derived/Build/Products/Release-iphoneos/Asabunko.app build/ipa/Payload/Asabunko.app
# An ad-hoc signature carries the App Group of the widget. A sideload tool reads the
# entitlements from it when it signs the app, so the widget and the app share their folder.
app=build/ipa/Payload/Asabunko.app
codesign -f -s - --entitlements Widget/Widget.entitlements "$app/PlugIns/AsabunkoWidget.appex"
codesign -f -s - --entitlements App/Asabunko.entitlements "$app"
(cd build/ipa && zip -qry ../Asabunko.ipa Payload)
echo "build/Asabunko.ipa"
