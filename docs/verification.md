# 验证记录 · 2026-10-27

环境：Windows，无 Swift / Xcode / macOS SDK。

已执行：
- Info.plist 可由 XML 解析器读取。
- 构建脚本通过 Git Bash 的 bash -n 语法检查。
- Git whitespace 检查。
- 独立静态审阅：检查 AppKit 使用、Services、组合输入、异步状态和原生撤销。

审阅后修改：
- 删除不恰当的 Services 内容类型限制。
- 不再仅依赖 SwiftUI 文本字符串变化；由 NSTextView 的内容与选区变化报告组合状态。
- 程序替换使用 shouldChangeText / textStorage / didChangeText 原生编辑流程，并设置撤销操作名。
- 外部结果展示对应原文。

未执行：
- swift test（包括新增六个测试）；未取得 RED/GREEN 运行结果。
- 原生应用编译、启动、AX 权限、Services 注册。
- 拼音、ABC、撤销和第三方应用实测。
- Ollama 真实模型端到端调用。
- GitHub Actions；目前只添加配置，尚未推送。

结论：提供待 Mac 构建和验收的原生早期源码，不称为已验证安装包。后续以 CI 和实机记录更新本文件。
