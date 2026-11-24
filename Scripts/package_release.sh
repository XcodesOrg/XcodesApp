#!/bin/bash
# Build and export the app with local signing assets, then create Product/Xcodes.zip.
set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf Archive/*
rm -rf Product/*

xcodebuild archive -project Xcodes.xcodeproj -scheme Xcodes -archivePath Archive/Xcodes.xcarchive \
    -derivedDataPath Archive/DerivedData
xcodebuild -exportArchive -archivePath Archive/Xcodes.xcarchive -exportPath Product/Xcodes \
    -exportOptionsPlist Scripts/export_options.plist
cp -a Product/Xcodes/Xcodes.app Product/Xcodes.app

/usr/bin/ditto -c -k --sequesterRsrc --keepParent Product/Xcodes.app Product/Xcodes.zip
