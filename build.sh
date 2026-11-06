#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/BashMacDuler.app"
ARCH="$(uname -m)"

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Не найден Swift. Установите Xcode Command Line Tools: xcode-select --install"
    exit 1
fi
if ! command -v sips >/dev/null 2>&1 || ! command -v iconutil >/dev/null 2>&1; then
    echo "Для подготовки иконки нужны sips и iconutil (входят в macOS)."
    exit 1
fi
if [[ ! -f "$ROOT/icon.png" ]]; then
    echo "Не найден файл иконки: $ROOT/icon.png"
    exit 1
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/BashMacDulerBuild.XXXXXX")"
TEMP_APP="$TEMP_ROOT/BashMacDuler.app"
ICONSET="$TEMP_ROOT/BashMacDuler.iconset"
trap 'rm -rf "$TEMP_ROOT"' EXIT

mkdir -p "$BUILD_DIR" "$TEMP_APP/Contents/MacOS" "$TEMP_APP/Contents/Resources"
mkdir -p "$ICONSET"

sips -z 16 16 "$ROOT/icon.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ROOT/icon.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ROOT/icon.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ROOT/icon.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ROOT/icon.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ROOT/icon.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ROOT/icon.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ROOT/icon.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ROOT/icon.png" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ROOT/icon.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil --convert icns --output "$TEMP_APP/Contents/Resources/BashMacDuler.icns" "$ICONSET"

SOURCES=("$ROOT"/Sources/*.swift)
xcrun swiftc \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -sdk "$SDK_PATH" \
    -target "${ARCH}-apple-macosx12.0" \
    -framework AppKit \
    -framework SwiftUI \
    -framework UserNotifications \
    "${SOURCES[@]}" \
    -o "$TEMP_APP/Contents/MacOS/BashMacDuler"

cp "$ROOT/Info.plist" "$TEMP_APP/Contents/Info.plist"
plutil -lint "$TEMP_APP/Contents/Info.plist"
codesign --force --sign - "$TEMP_APP" >/dev/null
codesign --verify --deep --strict "$TEMP_APP"

rm -rf "$APP_DIR"
ditto "$TEMP_APP" "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true

echo "Готово: $APP_DIR"
