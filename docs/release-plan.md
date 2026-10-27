# 可安装版本交付计划

目标：推送 GitHub，真实 macOS 编译测试，修复失败，发布可下载 DMG，完善首次运行和设置。

架构：延续原生 SwiftUI / AppKit；保留苹果输入源；本机 Ollama 与用户主动配置的 HTTPS Chat Completions 兼容服务二选一。云端使用前需在设置同意发送当前句子，密钥按端点存放 Keychain。无免费内置模型或平台密钥。

任务：
- [x] 推送开发分支，启动 Intel / Apple Silicon CI。
- [ ] 针对 CI 根因修复编译、测试问题。
- [ ] 原生品牌视觉、首次使用引导、设置分类、收藏、模型检测、服务验证与清空操作。
- [ ] 服务端点验证、响应解析、请求版本隔离及对应测试。
- [ ] 图标、DMG 拖入 Applications、签名检查和启动冒烟测试。
- [ ] 双架构通过后创建 GitHub Release、README 直接下载链接、合并主分支。

约束：无 Developer ID 凭证时只能 ad-hoc 签名，不能宣称公证或无系统警告。不得关闭 Gatekeeper 或提供绕过系统保护的命令。README 提供系统“隐私与安全性 → 仍要打开”的正常用户操作说明。

验证：swift test、release 编译、codesign verify、hdiutil verify、打包内容检查、原生 app 启动存活、截图。真实候选词交互与第三方兼容不由编译测试证明。
