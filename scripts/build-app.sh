#!/bin/bash
# 编译 release → 组装 build/MyKit.app → 用固定证书签名
set -euo pipefail
cd "$(dirname "$0")/.."

KEYCHAIN="$HOME/Library/Keychains/mykit-dev.keychain-db"
KEYCHAIN_PASSWORD="mykit-dev"
IDENTITY="MyKit Dev"
APP="build/MyKit.app"

if [[ ! -f "$KEYCHAIN" ]]; then
  echo "error: 未找到签名证书，请先运行 scripts/create-dev-cert.sh" >&2
  exit 1
fi

swift build -c release --build-system native

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MyKit "$APP/Contents/MacOS/MyKit"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
codesign --force --keychain "$KEYCHAIN" -s "$IDENTITY" --identifier com.imiros.mykit "$APP"
codesign --verify --strict "$APP"
codesign -d -r- "$APP" 2>&1 | grep '^designated'

echo "完成：$APP"
