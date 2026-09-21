#!/bin/bash
# 制作安装包 build/MyKit-<版本号>.dmg：MyKit.app + "应用程序"快捷方式 + 安装说明。仅支持 Apple 芯片的 Mac。
set -euo pipefail
cd "$(dirname "$0")/.."

KEYCHAIN="$HOME/Library/Keychains/mykit-dev.keychain-db"
KEYCHAIN_PASSWORD="mykit-dev"
IDENTITY="MyKit Dev"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
DMG="build/MyKit-$VERSION.dmg"
STAGE="build/dmg-staging"

scripts/build-app.sh
echo "芯片架构: $(lipo -archs build/MyKit.app/Contents/MacOS/MyKit)"

# 只清理自己 build/ 目录下的临时文件夹
if [[ -d "$STAGE" ]]; then rm -r "$STAGE"; fi
mkdir -p "$STAGE"
cp -R build/MyKit.app "$STAGE/MyKit.app"
ln -s /Applications "$STAGE/Applications"
cp Resources/安装说明.txt "$STAGE/安装说明.txt"

if [[ -f "$DMG" ]]; then rm "$DMG"; fi
hdiutil create -volname "MyKit $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -r "$STAGE"

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
codesign --force --keychain "$KEYCHAIN" -s "$IDENTITY" "$DMG"

SIZE="$(du -h "$DMG" | awk '{print $1}')"
echo "完成：${DMG}  大小 ${SIZE}"
