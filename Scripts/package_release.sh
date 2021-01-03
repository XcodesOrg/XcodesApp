#!/bin/bash
#
# Package release
#
# This will build and archive the app and then compress it in a .zip file
# You must already have all required code signing assets installed on your computer

PROJECT_NAME=Xcodes
PROJECT_DIR=$(pwd)/$PROJECT_NAME/Resources
SCRIPTS_DIR=$(pwd)/Scripts
INFOPLIST_FILE="Info.plist"

CFBundleVersion=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${PROJECT_DIR}/${INFOPLIST_FILE}")
CFBundleShortVersionString=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${PROJECT_DIR}/${INFOPLIST_FILE}")

# Ensure a clean build
rm -rf Archive/*
rm -rf Product/*
xcodebuild clean -project $PROJECT_NAME.xcodeproj -configuration Release -alltargets

# Archive the app and export for release distribution
xcodebuild archive -project $PROJECT_NAME.xcodeproj -scheme $PROJECT_NAME -archivePath Archive/$PROJECT_NAME.xcarchive
xcodebuild -archivePath Archive/$PROJECT_NAME.xcarchive -exportArchive -exportPath Product/$PROJECT_NAME.app -exportOptionsPlist "${SCRIPTS_DIR}/export_options.plist"
zip -r "Product/$PROJECT_NAME.v${CFBundleShortVersionString}.b${CFBundleVersion}.zip" Product/$PROJECT_NAME.app
