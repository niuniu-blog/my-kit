#!/bin/bash
# 把 build/MyKit.app 安装到 /Applications 并启动
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -d build/MyKit.app ]]; then
  echo "error: 还没有构建，请先运行 scripts/build-app.sh" >&2
  exit 1
fi

pkill -x MyKit || true
sleep 1
rm -rf /Applications/MyKit.app
cp -R build/MyKit.app /Applications/MyKit.app
open /Applications/MyKit.app
echo "已安装并启动：/Applications/MyKit.app（看屏幕右上角的图标）"
