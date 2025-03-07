#!/bin/sh
#
# Notarize
#
# Uploads to Apple's notarization service, polls until it completes, staples the ticket to the built app, then creates a new zip.
#
# Requires four arguments:
#   - Apple Account username
#   - Apple Account app-specific password (store this in your Keychain and use the @keychain:$NAME syntax to prevent your password from being added to your shell history)
#   - App Store Connect provider name
#   - Path to .app to upload
#
# Assumes that there's a .app beside the .zip with the same name so it can be stapled and re-zipped.
#
# E.g. notarize.sh "test@example.com" "@keychain:altool" MyOrg Xcodes.zip
#
# https://developer.apple.com/documentation/xcode/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow
# Adapted from https://github.com/keybase/client/blob/46f5df0aa64ff19198ba7b044bbb7cd907c0be9f/packaging/desktop/package_darwin.sh

file="$1"
team_id="$2"

echo "Uploading to notarization service"

result=$(xcrun notarytool submit "$file" \
    --keychain-profile "AC_PASSWORD" \
    --team-id "$team_id" \
    --wait) 
# echo "done1"
echo $result

# My grep/awk is bad and I can't figure out how to get the UUID out properly
# uuid=$("$result" | \
#     grep 'id:' | tail -n1 | \
#     cut -d":" -f2-)

echo "Successfully uploaded to notarization service, polling for result: $uuid"

# we should check here using the info (or notarytool log) to check the results and log
# 

#     fullstatus=$(xcrun notarytool info "$uuid" \
#         --keychain-profile "AC_PASSWORD" 2>&1)
#     status=$(echo "$fullstatus" | grep 'status\:' | awk '{ print $2 }')
#     if [ "$status" = "Accepted" ]; then
#       echo "Notarization success"
#       exit 0
#     else
#       echo "Notarization failed, full status below"
#       echo "$fullstatus"
#       exit 1
#     fi

# Remove .zip
rm $file

# Staple ticket to .app
app_path="$(basename -s ".zip" "$file").app"
xcrun stapler staple "$app_path"

# Zip the stapled app for distribution
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$file"
