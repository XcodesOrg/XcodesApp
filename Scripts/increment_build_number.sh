#!/bin/sh
#
# Increment build number
#
# This will get the latest build number from git tags, add 1, then set it in the Info.plist.
# Assumes that build numbers are monotonically increasing positive integers, across version numbers.
# Tags must be named v$version_numberb$build_number, e.g. v1.2.3b456

infoplist_file="$(pwd)/Xcodes/Resources/Info.plist"

# Get latest tag hash matching pattern
hash=$(git rev-list --tags="v" --max-count=1)
# Get latest tag at hash that matches the same pattern as a prefix in order to support commits with multiple tags
last_tag=$(git describe --tags --match "v*" "$hash")
# Get build number from last component of tag name
last_build_number=$(echo "$last_tag" | grep -o "b.*" | cut -c 2-)

build_number=$(($last_build_number + 1))

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "${infoplist_file}"
