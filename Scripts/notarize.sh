#!/bin/sh
# Notarize Xcodes.zip, staple the sibling Xcodes.app, and repackage it.
set -eu

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <archive.zip> <Apple Developer team ID>" >&2
    exit 1
fi

archive=$1
team_id=$2
app="${archive%.zip}.app"
test -f "$archive"
test -d "$app"

temp_dir=$(mktemp -d "$(dirname "$archive")/.notarize.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT
result="$temp_dir/result.json"

echo "Submitting $archive to Apple for notarization"
if ! xcrun notarytool submit "$archive" --keychain-profile AC_PASSWORD --team-id "$team_id" \
    --wait --timeout 30m --output-format json > "$result"; then
    cat "$result" >&2
    exit 1
fi

status=$(plutil -extract status raw -o - "$result")
submission_id=$(plutil -extract id raw -o - "$result")
if [ "$status" != Accepted ]; then
    echo "Notarization status: $status (submission $submission_id)" >&2
    xcrun notarytool log "$submission_id" --keychain-profile AC_PASSWORD --team-id "$team_id" >&2 || true
    exit 1
fi

xcrun stapler staple "$app"
xcrun stapler validate "$app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$temp_dir/stapled.zip"
mv "$temp_dir/stapled.zip" "$archive"
