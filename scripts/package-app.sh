#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}/.."
cd "$ROOT_DIR"

APP_NAME="清爽 Mac.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
APP_DIR="$ROOT_DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="$MACOS_DIR/CleanMyMac"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

swift build -c release --product CleanMyMac

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/release/CleanMyMac" "$EXECUTABLE"

plutil -create xml1 "$INFO_PLIST"
plutil -insert CFBundleDisplayName -string "清爽 Mac" "$INFO_PLIST"
plutil -insert CFBundleExecutable -string "CleanMyMac" "$INFO_PLIST"
plutil -insert CFBundleIdentifier -string "com.qingshuangmac.personal" "$INFO_PLIST"
plutil -insert CFBundleName -string "清爽 Mac" "$INFO_PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$INFO_PLIST"
plutil -insert CFBundleShortVersionString -string "0.1.0" "$INFO_PLIST"
plutil -insert CFBundleVersion -string "1" "$INFO_PLIST"
plutil -insert LSMinimumSystemVersion -string "13.0" "$INFO_PLIST"
plutil -insert CFBundleDevelopmentRegion -string "zh_CN" "$INFO_PLIST"
plutil -insert CFBundleIconFile -string "AppIcon" "$INFO_PLIST"

ICONSET_DIR="$ROOT_DIR/Resources/AppIcon.iconset"
mkdir -p "$ROOT_DIR/Resources"
swift "$ROOT_DIR/scripts/generate-app-icon.swift" "$ICONSET_DIR"
iconutil --convert icns --output "$ROOT_DIR/Resources/AppIcon.icns" "$ICONSET_DIR"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP_DIR"
    SIGNING_DESCRIPTION="本地临时签名（无需 Apple 开发者账号）"
else
    codesign --force --options runtime --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_DIR"
    SIGNING_DESCRIPTION="本机固定证书：$SIGNING_IDENTITY"
fi

print "已生成：$APP_DIR"
print "签名：$SIGNING_DESCRIPTION"
