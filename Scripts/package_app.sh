#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ZipForge"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
VERSION="${ZIPFORGE_VERSION:-0.1.0}"
BUNDLE_ID="com.zipforge.ZipForge"

cd "$ROOT_DIR"

swift build -c release

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

cp "$ROOT_DIR/.build/release/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_TW</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

echo "APPL????" > "$CONTENTS_DIR/PkgInfo"

python3 - "$ICONSET_DIR" <<'PY'
import struct
import subprocess
import sys
from pathlib import Path

iconset = Path(sys.argv[1])
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
    radius = size * 0.2
    inside = margin <= x <= size - margin and margin <= y <= size - margin
    if not inside:
        return (31, 41, 55)
    stripe = int((y - margin) / max(1, (size - 2 * margin) / 3))
    colors = [(37, 99, 235), (15, 118, 110), (202, 138, 4)]
    if abs(x - size / 2) < max(1, size * 0.018):
        return (17, 24, 39)
    return colors[min(2, max(0, stripe))]

for size, name in sizes:
    ppm = iconset / f"{name}.ppm"
    png = iconset / name
    with ppm.open("wb") as f:
        f.write(f"P6\n{size} {size}\n255\n".encode("ascii"))
        for y in range(size):
            for x in range(size):
                f.write(struct.pack("BBB", *pixel(x, y, size)))
    subprocess.run(["/usr/bin/sips", "-s", "format", "png", str(ppm), "--out", str(png)], check=True, stdout=subprocess.DEVNULL)
    ppm.unlink()
PY

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

/usr/bin/codesign --force --deep --sign - "$APP_DIR"

echo "Created $APP_DIR"
