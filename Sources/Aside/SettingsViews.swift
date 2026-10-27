import SwiftUI
import AsideCore

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var assistant: AssistantModel
    @State private var permissionMessage = ""

    var body: some View {
        TabView {
            Form {
                Section("你的表达习惯") {
                    Picker("英文风格", selection: $preferences.style) {
                        ForEach(ExpressionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker("使用方式", selection: $preferences.outputMode) {
                        Text("学习对照").tag(false)
                        Text("英文输出").tag(true)
                    }.pickerStyle(.segmented)
                    Text("中文翻译成英文，英文改写成英文，均附中文讲解。英文输出仅在确认后替换句外编辑区。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("显示与触发") {
                    Toggle("写完一句自动处理（句外编辑区）", isOn: $preferences.autoDraft)
                    Toggle("默认展开中文讲解", isOn: $preferences.showExplanation)
                    Toggle("暂停句外", isOn: $preferences.paused)
                    Text("英文以浅灰字排在原文下方，点击译文展开操作。输入源切换沿用系统设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("其他应用 · 实验性") {
                    Toggle("自动检测备忘录 / 文本编辑", isOn: $preferences.automatic)
                    Text("开启后读取允许应用的当前文本框，句末稳定后处理；最多处理 2000 字。无法可靠判断所有组合输入状态，每次启动默认关闭。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("检查 / 请求辅助功能权限") {
                        assistant.accessibility.requestPermission()
                        permissionMessage = assistant.accessibility.trusted ? "辅助功能已授权。" : "请在系统设置 → 隐私与安全性 → 辅助功能中授权句外。"
                    }
                    if !permissionMessage.isEmpty { Text(permissionMessage).font(.caption) }
                    Text("跨应用只复制结果，不自动替换或发送；不支持全应用框内灰字。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("常规", systemImage: "slider.horizontal.3") }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("连接你的翻译服务").font(.title3.weight(.semibold))
                    Text("本机与云端二选一。没有内置账户、赠送额度或预装模型。")
                        .font(.callout).foregroundStyle(.secondary)
                    ServiceSetupView(preferences: preferences, assistant: assistant)
                }.padding(24)
            }.tabItem { Label("翻译服务", systemImage: "network") }
            SavedView(assistant: assistant).tabItem { Label("收藏", systemImage: "bookmark") }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    BrandMark(size: 52)
                    Text("安静一点，也懂你一点。").font(.title2.weight(.medium))
                    privacy("保留原生输入", "中文用苹果拼音，英文用 ABC。候选词、Caps Lock、地球键与系统切换均由 macOS 管理。")
                    privacy("你决定文字去哪里", "本机模式连接 localhost；云端模式发送到你配置并同意的 HTTPS 服务。API Key 按地址存入 Mac 钥匙串。")
                    privacy("只留下你主动收藏的句子", "不自动保存输入历史。收藏保存在当前 Mac，可随时移除；清空编辑区可清除当前原文和译文。")
                    privacy("目前的边界", "跨应用框内提示仍受系统和宿主应用限制。此预览版尚未 Apple Developer ID 签名或公证。")
                    Link("项目与更新 ↗", destination: URL(string: "https://github.com/pengruoxin/Aside")!)
                    Text("句外 Aside · v0.2.0 · MIT").font(.caption).foregroundStyle(.tertiary)
                }.padding(26)
            }.tabItem { Label("隐私与关于", systemImage: "hand.raised") }
        }
        .padding(12).frame(minWidth: 590, idealWidth: 620, minHeight: 610, idealHeight: 660)
        .tint(AsideTheme.accent)
    }

    private func privacy(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SavedView: View {
    @ObservedObject var assistant: AssistantModel
    var body: some View {
        if assistant.saved.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "bookmark").font(.system(size: 32)).foregroundStyle(AsideTheme.accent.opacity(0.7))
                Text("留下想记住的表达").font(.title3)
                Text("点击译文展开详情，再选择收藏。\n仅主动收藏的句子会保存到本机。")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(assistant.saved) { entry in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text(entry.style.title).font(.caption).foregroundStyle(AsideTheme.accent)
                            Spacer()
                            Button("移除") { assistant.removeSaved(entry.id) }.buttonStyle(.borderless)
                        }
                        Text(entry.expression).font(.system(size: 17, design: .serif)).textSelection(.enabled)
                        Text(entry.source).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        DisclosureGroup("表达点拨") { Text(entry.explanation).font(.callout).foregroundStyle(.secondary) }
                        Button("复制英文") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.expression, forType: .string)
                        }.controlSize(.small)
                    }.padding(.vertical, 10)
                }
            }
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var assistant: AssistantModel
    @ObservedObject var preferences: Preferences
    var finish: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BrandMark(size: 58)
                Text("你好，句外。").font(.largeTitle.weight(.semibold))
                Text("中文照常写，英文顺手学。").font(.title3).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 20) {
                    step("1", "保留苹果输入", "拼音、ABC 和切换键照常用")
                    step("2", "连接翻译服务", "选本机模型或自己的云端 API")
                    step("3", "从一句话开始", "选中文字，通过系统服务处理")
                }
                Divider()
                ServiceSetupView(preferences: preferences, assistant: assistant)
                Divider()
                Text("跨应用：选中文字 → 原应用菜单“服务”→“使用句外处理”，然后从菜单栏查看结果。框内灰字目前仅在句外编辑区实现。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("稍后设置") { finish() }
                    Spacer()
                    Button("开始使用") { finish() }.buttonStyle(.borderedProminent).disabled(preferences.needsSetup)
                }
            }.padding(32)
        }.frame(width: 620, height: 680).tint(AsideTheme.accent)
    }
    private func step(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(number).font(.caption.weight(.semibold)).foregroundStyle(AsideTheme.accent)
            Text(title).font(.callout.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
