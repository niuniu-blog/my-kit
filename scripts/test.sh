#!/bin/bash
# 跑全部单元测试。额外参数原样传给 swift test，例如：scripts/test.sh --filter DoubleTapDetectorTests
set -euo pipefail
cd "$(dirname "$0")/.."

DEV_DIR="$(xcode-select -p)"
ARGS=(--build-system native)
# 只有 Command Line Tools（没有 Xcode）时，Swift Testing 的框架、宏插件和运行时路径都要手动指定
if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
  FW="$DEV_DIR/Library/Developer/Frameworks"
  ARGS+=(
    -Xswiftc "-F$FW"
    -Xswiftc -plugin-path -Xswiftc "$DEV_DIR/usr/lib/swift/host/plugins/testing"
    -Xlinker "-F$FW"
    -Xlinker -rpath -Xlinker "$FW"
    -Xlinker -rpath -Xlinker "$DEV_DIR/Library/Developer/usr/lib"
  )
fi

swift test "${ARGS[@]}" "$@"
