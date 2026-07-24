#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ZipForge"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode"
BUILT_APP_DIR="$DERIVED_DATA_DIR/Build/Products/Release/$APP_NAME.app"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
EXTENSION_DIR="$APP_DIR/Contents/PlugIns/ZipForgeFinderSync.appex"
SWIFT_CONCURRENCY_LIBRARY="$APP_DIR/Contents/Frameworks/libswift_Concurrency.dylib"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
VERSION="${ZIPFORGE_VERSION:-0.2.0}"
BUILD_NUMBER="${ZIPFORGE_BUILD_NUMBER:-1}"

cd "$ROOT_DIR"

xcodebuild \
    -project "$ROOT_DIR/ZipForge.xcodeproj" \
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

python3 - "$ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns" <<'PY'
import binascii
import struct
import sys
import zlib
from pathlib import Path

iconset = Path(sys.argv[1])
icns_path = Path(sys.argv[2])
sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

def pixel(x, y, size):
    margin = size * 0.18
    inside = margin <= x <= size - margin and margin <= y <= size - margin
    if not inside:
        return (31, 41, 55, 255)
    stripe = int((y - margin) / max(1, (size - 2 * margin) / 3))
    colors = [(37, 99, 235), (15, 118, 110), (202, 138, 4)]
    if abs(x - size / 2) < max(1, size * 0.018):
        return (17, 24, 39, 255)
    return (*colors[min(2, max(0, stripe))], 255)

def chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", binascii.crc32(kind + data) & 0xffffffff)
    )

def write_png(path, size):
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            rows.extend(pixel(x, y, size))

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + chunk(b"IEND", b"")
    )

for size, name in sizes:
    write_png(iconset / name, size)

icns_entries = [
    (b"icp4", "icon_16x16.png"),
    (b"icp5", "icon_32x32.png"),
    (b"icp6", "icon_32x32@2x.png"),
    (b"ic07", "icon_128x128.png"),
    (b"ic08", "icon_256x256.png"),
    (b"ic09", "icon_512x512.png"),
    (b"ic10", "icon_512x512@2x.png"),
    (b"ic11", "icon_16x16@2x.png"),
    (b"ic12", "icon_32x32@2x.png"),
    (b"ic13", "icon_128x128@2x.png"),
    (b"ic14", "icon_256x256@2x.png"),
]
payload = bytearray()
for kind, filename in icns_entries:
    data = (iconset / filename).read_bytes()
    payload.extend(kind)
    payload.extend(struct.pack(">I", len(data) + 8))
    payload.extend(data)

icns_path.write_bytes(
    b"icns"
    + struct.pack(">I", len(payload) + 8)
    + payload
)
PY

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
    --entitlements "$ROOT_DIR/Config/ZipForgeFinderSync.entitlements" \
    "$EXTENSION_DIR"
/usr/bin/codesign --force --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"

echo "Created $APP_DIR"
