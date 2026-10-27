# 验证记录 · 2026-10-27

开发环境：Windows。原生测试通过 GitHub Actions 在真实 macOS runner 中执行。

## 已获得的运行结果

- [初版双架构构建](https://github.com/pengruoxin/Aside/actions/runs/40467251567)：Swift 测试和 release 编译通过。
- [原生界面与 DMG 构建](https://github.com/pengruoxin/Aside/actions/runs/40468132288)：Apple Silicon / Intel 均通过 10 个测试、原生启动、NSTextView 编辑撤销、图标生成、签名校验、DMG 校验。
- [服务协议与界面修正](https://github.com/pengruoxin/Aside/actions/runs/40468640682)：两种架构各 14 个测试通过，生成实际原生截图和 DMG。网络测试使用 URLProtocol 模拟，不调用真实付费服务。

- [v0.2.0 发布验证](https://github.com/pengruoxin/Aside/actions/runs/40469762051)：Apple Silicon / Intel 各 15 个测试零失败，原生启动、编辑撤销、DMG 校验及 Release 发布全部通过。
- 已从公开 Release 下载两份 DMG，并核对 SHA-256 与发布的校验文件一致。
- [安装包下载](https://github.com/pengruoxin/Aside/releases/tag/v0.2.0)。

## 审阅后处理

- 去掉不恰当的 Services 内容类型限制。
- NSTextView 明确报告组合状态，不再只依赖 SwiftUI 字符串变化。
- 程序替换走原生编辑和撤销流程，之后重算高度。
- 区分手动选区与自动检测，避免自动读取失败清掉手动结果。
- 长译文在菜单栏和主窗口均可滚动。
- 云端 HTTPS 地址校验，拒绝 URL 内密钥 / 查询参数，禁止重定向转发。
- Keychain 按服务地址隔离；云端发送需本次明确同意。

## 仍需真实用户 Mac 验收

- 苹果拼音候选与上屏的完整交互、系统服务注册及快捷键。
- 备忘录 / 文本编辑的 AX 自动检测，浏览器和聊天工具的手动服务。
- macOS 13 / 14 以及其他版本的实际运行；当前 CI 为 macOS 15。
- 真实模型翻译质量、服务商兼容性、性能和资源占用。
- Developer ID 签名、公证和 Gatekeeper 的公开分发体验。

CI 的原生启动与编辑撤销检查不证明全应用兼容；当前发布为可安装预览版。
