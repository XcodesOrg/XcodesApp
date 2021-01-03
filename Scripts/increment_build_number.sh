#!/bin/sh
PROJECT_DIR=$(pwd)/Xcodes/Resources
INFOPLIST_FILE="Info.plist"
buildString=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${PROJECT_DIR}/${INFOPLIST_FILE}")
buildDate=$(echo $buildString | cut -c 1-8)
buildNumber=$(echo $buildString | cut -c 9-11)
today=$(date +'%Y%m%d')

if [[ $buildDate = $today ]]
then
buildNumber=$(($buildNumber + 1))
else
buildNumber=1
fi

buildString=$(printf '%s%03u' $today $buildNumber)

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildString" "${PROJECT_DIR}/${INFOPLIST_FILE}"
