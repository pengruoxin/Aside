#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
model="dist/安装句外.app/Contents/Resources/Aside.app/Contents/Resources/Models/qwen2.5-1.5b-instruct-q4_k_m.gguf"
[[ -f "$model" ]] || { echo "Full offline model missing; refusing to label this as a complete offline installer."; exit 1; }
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "dist/安装句外.app" "$stage/安装句外.app"
cat > "$stage/安装与使用.txt" <<'EOF'
句外输入法 0.3.0 · 完整离线测试版

1. 打开“安装句外.app”，点击安装句外输入法。
2. 安装到当前用户 ~/Library/Input Methods/Aside.app。
3. 从系统输入源菜单选择“句外拼音”或“句外英文”。
4. 若未出现，请注销重新登录，再在键盘设置添加句外。

本包含拼音引擎、推理引擎和约1.1GB语言模型。
下载安装完成后可断网使用，无API Key、Ollama或云端服务。

空格/数字选词；Control–Option–T 翻译或改写当前句子。
Return 先确认拼音，再交给搜索框/聊天框的正常操作。
学习模式点英文候选看讲解；英文输出模式可Tab或点候选采用英文。
不会把英文提示自动混进搜索或消息正文。

请注意：当前采用原生候选区展示英文，不是通用框内灰字。
百度浏览器与已登录微信的真实交互仍需实机验收。
当前针对Apple Silicon、macOS26+，优先适配M5 16GB MacBook Air。

预览版无 Apple Developer ID 签名和公证。
核实来自本项目后，若系统阻止打开，可在“隐私与安全性”中确认。
不要关闭系统安全保护。
EOF
name="Aside-0.3.0-arm64-offline.dmg"
hdiutil create -volname "句外离线输入法" -srcfolder "$stage" -ov -format UDZO "dist/$name"
hdiutil verify "dist/$name"
(cd dist && shasum -a 256 "$name") > "dist/$name.sha256"
