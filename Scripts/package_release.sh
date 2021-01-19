#!/bin/bash
#
# Package release
#
# This will build and archive the app and then compress it in a .zip file at Product/Xcodes.zip
# You must already have all required code signing assets installed on your computer

PROJECT_NAME=Xcodes
PROJECT_DIR=$(pwd)/$PROJECT_NAME/Resources
SCRIPTS_DIR=$(pwd)/Scripts
INFOPLIST_FILE="Info.plist"

# Ensure a clean build
rm -rf Archive/*
rm -rf Product/*
xcodebuild clean -project $PROJECT_NAME.xcodeproj -configuration Release -alltargets

# Archive the app and export for release distribution
xcodebuild archive -project $PROJECT_NAME.xcodeproj -scheme $PROJECT_NAME -archivePath Archive/$PROJECT_NAME.xcarchive
xcodebuild -archivePath Archive/$PROJECT_NAME.xcarchive -exportArchive -exportPath Product/$PROJECT_NAME -exportOptionsPlist "${SCRIPTS_DIR}/export_options.plist"
cp -r "Product/$PROJECT_NAME/$PROJECT_NAME.app" "Product/$PROJECT_NAME.app"

# Create a ZIP archive suitable for altool.
/usr/bin/ditto -c -k --keepParent "Product/$PROJECT_NAME.app" "Product/$PROJECT_NAME.zip"
