#!/bin/bash
# 一键编译 + 安装原生小组件（需要 Xcode + xcodegen）
set -e
cd "$(dirname "${BASH_SOURCE[0]}")"

command -v xcodegen >/dev/null 2>&1 || { echo "需要 xcodegen：brew install xcodegen"; exit 1; }
[ -d /Applications/Xcode.app ] || { echo "需要完整 Xcode（App Store 安装）"; exit 1; }

xcodegen generate
xcodebuild -project M5VitalsWidget.xcodeproj -scheme M5VitalsNative \
  -configuration Release -derivedDataPath build build | tail -3

rm -rf /Applications/M5VitalsNative.app
ditto build/Build/Products/Release/M5VitalsNative.app /Applications/M5VitalsNative.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f /Applications/M5VitalsNative.app
pluginkit -a /Applications/M5VitalsNative.app/Contents/PlugIns/M5VitalsWidget.appex || true

echo
echo "✓ 已安装到 /Applications/M5VitalsNative.app"
echo "  下一步：桌面右键 →「编辑小组件」→ 搜索 M5Vitals → 拖到桌面"
echo "  刷新间隔可在右键小组件 →「编辑 M5Vitals」里选 1 / 5 / 15 / 30 分钟"
