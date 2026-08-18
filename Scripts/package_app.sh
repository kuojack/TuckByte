#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="TuckByte"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode"
BUILT_APP_DIR="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
EXTENSION_DIR="$APP_DIR/Contents/PlugIns/TuckByteFinderSync.appex"
SWIFT_CONCURRENCY_LIBRARY="$APP_DIR/Contents/Frameworks/libswift_Concurrency.dylib"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.png"
VERSION="${TUCKBYTE_VERSION:-0.8.0}"
BUILD_NUMBER="${TUCKBYTE_BUILD_NUMBER:-1}"

cd "$ROOT_DIR"

xcodebuild \
    -project "$ROOT_DIR/TuckByte.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    build

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$DIST_DIR" "$ICONSET_DIR"
cp -R "$BUILT_APP_DIR" "$APP_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$RESOURCES_DIR/ThirdPartyLicenses"
cp "$ROOT_DIR/ThirdParty/minizip-ng/LICENSE" \
    "$RESOURCES_DIR/ThirdPartyLicenses/minizip-ng.txt"
cp "$ROOT_DIR/ThirdParty/zstd/LICENSE" \
    "$RESOURCES_DIR/ThirdPartyLicenses/zstd.txt"
cp "$ROOT_DIR/ThirdParty/argon2/LICENSE" \
    "$RESOURCES_DIR/ThirdPartyLicenses/argon2.txt"

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "App icon source was not found at $ICON_SOURCE" >&2
    exit 1
fi

/usr/bin/sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

rm -rf "$ICONSET_DIR"

if [[ ! -d "$EXTENSION_DIR" ]]; then
    echo "Finder extension was not embedded at $EXTENSION_DIR" >&2
    exit 1
fi

if [[ -f "$SWIFT_CONCURRENCY_LIBRARY" ]]; then
    /usr/bin/codesign --force --sign - "$SWIFT_CONCURRENCY_LIBRARY"
fi
/usr/bin/codesign \
    --force \
    --sign - \
    --entitlements "$ROOT_DIR/Config/TuckByteFinderSync.entitlements" \
    "$EXTENSION_DIR"
/usr/bin/codesign --force --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

echo "Created $APP_DIR"
