#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
arch="$(uname -m)"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/Aside.app/Contents/Info.plist)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto dist/Aside.app "$stage/Aside.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/安装说明.txt" <<'EOF'
句外 Aside

将 Aside 拖入 Applications，然后从 Applications 打开。
菜单栏出现“句外”表示应用已运行。

首次运行需在设置选择本机 Ollama 或配置自己的 HTTPS 云端服务。
应用不包含免费模型、服务账号或 API Key。

此预览版暂未获得 Apple Developer ID 签名与公证。
若系统阻止打开，请核对 GitHub 官方发布来源，然后在系统设置
“隐私与安全性”中使用“仍要打开”。无需关闭系统安全保护。

中文继续用苹果拼音，英文继续用 ABC；句外不改输入源切换设置。
跨应用可选中文字，从原应用“服务”菜单选择“使用句外处理”。
原生句外编辑区支持框内浅灰英文；第三方应用不保证支持。
EOF
hdiutil create -volname "句外 Aside" -srcfolder "$stage" -ov -format UDZO "dist/Aside-$version-$arch.dmg"
hdiutil verify "dist/Aside-$version-$arch.dmg"
shasum -a 256 "dist/Aside-$version-$arch.dmg" > "dist/Aside-$version-$arch.dmg.sha256"
