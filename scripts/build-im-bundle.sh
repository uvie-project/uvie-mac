#!/bin/bash
# Assemble the UVieIM.app input-method bundle: the same UVieMac binary as
# the app, a dedicated Info.plist, and the app icon under the IM's icon
# name. Version strings are copied from the root Info.plist.
#
# Usage: build-im-bundle.sh <path-to-UVieMac-binary> <output-dir> [codesign-identity]
set -e

BINARY="$1"
OUT_DIR="$2"
IDENTITY="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP="$OUT_DIR/UVieIM.app"
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/UVieMac"
chmod +x "$CONTENTS/MacOS/UVieMac"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$ROOT_DIR/Info.plist")
cp "$ROOT_DIR/InputMethod/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$CONTENTS/Info.plist"

cp "$ROOT_DIR/AppIcon.icns" "$CONTENTS/Resources/UVieIM.icns"

if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime \
        --entitlements "$ROOT_DIR/UVieMac.entitlements" \
        --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
