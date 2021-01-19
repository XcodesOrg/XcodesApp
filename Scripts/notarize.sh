#!/bin/sh
#
# Notarize
#
# Uploads to Apple's notarization service, polls until it completes, staples the ticket to the built app, then creates a new zip.
#
# Requires four arguments:
#   - Apple ID username
#   - Apple ID app-specific password (store this in your Keychain and use the @keychain:$NAME syntax to prevent your password from being added to your shell history)
#   - App Store Connect provider name
#   - Path to .app to upload
#
# Assumes that there's a .app beside the .zip with the same name so it can be stapled and re-zipped.
#
# E.g. notarize.sh "test@example.com" "@keychain:altool" MyOrg Xcodes.zip
#
# https://developer.apple.com/documentation/xcode/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow
# Adapted from https://github.com/keybase/client/blob/46f5df0aa64ff19198ba7b044bbb7cd907c0be9f/packaging/desktop/package_darwin.sh

username="$1"
password="$2"
asc_provider="$3"
file="$4"

echo "Uploading to notarization service"

uuid=$(xcrun altool \
    --notarize-app \
    --primary-bundle-id "com.robotsandpencils.XcodesApp.zip" \
    --username "$username" \
    --password "$password" \
    --asc-provider "$asc_provider" \
    --file "$file" 2>&1 | \
    grep 'RequestUUID' | \
    awk '{ print $3 }')

echo "Successfully uploaded to notarization service, polling for result: $uuid"

sleep 15
  while :
  do
    fullstatus=$(xcrun altool \
        --notarization-info "$uuid" \
        --username "$username" \
        --password "$password" \
        --asc-provider "$asc_provider" 2>&1)
    status=$(echo "$fullstatus" | grep 'Status\:' | awk '{ print $2 }')
    if [ "$status" = "success" ]; then
      echo "Notarization success"
      exit 0
    elif [ "$status" = "in" ]; then
      echo "Notarization still in progress, sleeping for 15 seconds and trying again"
      sleep 15
    else
      echo "Notarization failed, full status below"
      echo "$fullstatus"
      exit 1
    fi
  done

# Remove .zip
rm $file

# Staple ticket to .app
app_path="$(basename -s ".zip" "$file").app"
xcrun stapler staple "$app_path"

# Zip the stapled app for distribution
zip -r "$file" "$app_path"
