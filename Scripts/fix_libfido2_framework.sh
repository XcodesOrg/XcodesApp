#!/bin/sh

set -e

FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks"
LIBFIDO_FRAMEWORK_PATH="${FRAMEWORKS_DIR}/libfido2.framework"

if [ -d "$LIBFIDO_FRAMEWORK_PATH" ] && [ -f "$LIBFIDO_FRAMEWORK_PATH/Info.plist" ] && [ ! -d "$LIBFIDO_FRAMEWORK_PATH/Versions" ]; then
    echo "Fixing libfido2.framework bundle structure..."

    mkdir -p "$LIBFIDO_FRAMEWORK_PATH/Versions/A/Resources"

    mv "$LIBFIDO_FRAMEWORK_PATH/Info.plist" "$LIBFIDO_FRAMEWORK_PATH/Versions/A/Resources/"
    mv "$LIBFIDO_FRAMEWORK_PATH/libfido2" "$LIBFIDO_FRAMEWORK_PATH/Versions/A/"
    if [ -f "$LIBFIDO_FRAMEWORK_PATH/LICENSE" ]; then
        mv "$LIBFIDO_FRAMEWORK_PATH/LICENSE" "$LIBFIDO_FRAMEWORK_PATH/Versions/A/"
    fi

    ln -sf A "$LIBFIDO_FRAMEWORK_PATH/Versions/Current"
    ln -sf Versions/Current/libfido2 "$LIBFIDO_FRAMEWORK_PATH/libfido2"
    ln -sf Versions/Current/Resources "$LIBFIDO_FRAMEWORK_PATH/Resources"
fi

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
for item in \
    "$BUILT_PRODUCTS_DIR/libcrypto.3.dylib" \
    "$BUILT_PRODUCTS_DIR/libcbor.0.11.0.dylib" \
    "$FRAMEWORKS_DIR/libcrypto.3.dylib" \
    "$FRAMEWORKS_DIR/libcbor.0.11.0.dylib" \
    "$LIBFIDO_FRAMEWORK_PATH"; do
    if [ -e "$item" ]; then
        codesign --force --sign "$SIGN_IDENTITY" "$item"
    fi
done
