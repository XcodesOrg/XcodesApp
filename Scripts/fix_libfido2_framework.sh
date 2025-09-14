#!/bin/sh

# Fix libfido2.framework structure for macOS validation
FRAMEWORK_PATH="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Frameworks/libfido2.framework"

if [ -d "$FRAMEWORK_PATH" ] && [ -f "$FRAMEWORK_PATH/Info.plist" ] && [ ! -d "$FRAMEWORK_PATH/Versions" ]; then
    echo "Fixing libfido2.framework bundle structure..."

    # Create proper bundle structure
    mkdir -p "$FRAMEWORK_PATH/Versions/A/Resources"

    # Move files to proper locations
    mv "$FRAMEWORK_PATH/Info.plist" "$FRAMEWORK_PATH/Versions/A/Resources/"
    #mv "$FRAMEWORK_PATH/libfido2" "$FRAMEWORK_PATH/Versions/A/"
    #if [ -f "$FRAMEWORK_PATH/LICENSE" ]; then
    #    mv "$FRAMEWORK_PATH/LICENSE" "$FRAMEWORK_PATH/Versions/A/"
    #fi

    # Create symbolic links
    ln -sf A "$FRAMEWORK_PATH/Versions/Current"
    ln -sf Versions/Current/libfido2 "$FRAMEWORK_PATH/libfido2"
    ln -sf Versions/Current/Resources "$FRAMEWORK_PATH/Resources"

    echo "libfido2.framework structure fixed"
fi
