import SwiftUI
import AsideCore

struct ResultView: View {
    @ObservedObject var assistant: AssistantModel
    @ObservedObject var preferences: Preferences
    var inline = false

    var body: some View {
        if let result = assistant.result {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    assistant.explanationExpanded.toggle()
                } label: {
                    Text(result.expression)
                        .font(.system(size: inline ? 15 : 17, design: .serif))
                        .foregroundStyle(inline ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .help("点击查看中文讲解和操作")
                if assistant.explanationExpanded {
                    Text(result.explanation).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button("复制英文") { assistant.copyResult() }
                        if inline && !assistant.isExternal && preferences.outputMode {
                            Button("替换原句") { assistant.replaceDraft() }
                        }
                    }
                }
            }
        }
    }
}

struct WritingView: View {
    @ObservedObject var assistant: AssistantModel
    @ObservedObject var preferences: Preferences

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("句外 Aside").font(.title2.weight(.semibold))
                Spacer()
                Text(preferences.style.title).font(.caption).foregroundStyle(.secondary)
            }
            Text("中文照常写，英文顺手学。").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                NativeEditor(text: $assistant.draft, edited: { marked in
                    assistant.composing = marked
                    assistant.draftChanged()
                })
                    .frame(minHeight: 110, idealHeight: 150)
                if !assistant.isExternal {
                    ResultView(assistant: assistant, preferences: preferences, inline: true)
                        .padding(.horizontal, 14).padding(.bottom, assistant.result == nil ? 0 : 14)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
            HStack {
                if assistant.busy { ProgressView().controlSize(.small) }
                Text(assistant.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                Button("处理整段") { assistant.processDraft() }.disabled(preferences.paused || assistant.busy)
            }
            if assistant.isExternal {
                Divider()
                Text("来自其他应用 · 仅处理选中内容").font(.caption).foregroundStyle(.secondary)
                Text(assistant.resultSource).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                ResultView(assistant: assistant, preferences: preferences)
            }
            Spacer(minLength: 0)
            Text("使用系统拼音与 ABC；支持你的现有输入源切换设置。此处英文提示不属于可输入正文。")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(24).frame(minWidth: 500, minHeight: 380)
    }
}

struct MenuContent: View {
    @ObservedObject var assistant: AssistantModel
    @ObservedObject var preferences: Preferences
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("句外 Aside").font(.headline); Spacer(); Text(preferences.style.title).font(.caption).foregroundStyle(.secondary) }
            Text(assistant.message).font(.caption).foregroundStyle(.secondary)
            if assistant.busy { ProgressView().controlSize(.small) }
            if assistant.isExternal && !assistant.resultSource.isEmpty {
                Text(assistant.resultSource).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            }
            ResultView(assistant: assistant, preferences: preferences)
            Divider()
            Button("读取当前应用选中文字") { assistant.processSelection() }.disabled(preferences.paused)
            Button("打开句外编辑区") { openWindow(id: "writing"); NSApp.activate(ignoringOtherApps: true) }
            Button("偏好设置…") { openWindow(id: "preferences"); NSApp.activate(ignoringOtherApps: true) }
            Toggle("暂停句外", isOn: $preferences.paused)
            Divider()
            Text("也可使用原应用菜单：服务 → 使用句外处理。\n不会修改中文候选词和系统切换键。")
                .font(.caption).foregroundStyle(.secondary)
            Button("退出句外") { NSApp.terminate(nil) }
        }.padding(18).frame(width: 350)
    }
}

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var assistant: AssistantModel
    @State private var permissionMessage = ""

    var body: some View {
        Form {
            Section("表达") {
                Picker("英文风格", selection: $preferences.style) {
                    ForEach(ExpressionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("英文输出（允许替换句外编辑区）", isOn: $preferences.outputMode)
                Toggle("默认展开中文讲解", isOn: $preferences.showExplanation)
                Text("中文输入：翻译成英文。英文输入：改写英文。均附中文讲解。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("本机翻译服务") {
                TextField("Ollama 模型名", text: $preferences.model, prompt: Text("填写已安装的模型名"))
                Text("连接 localhost:11434。需自行安装 Ollama 和支持中英双语的模型；当前版本不发送至公网。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("其他应用 · 实验性") {
                Toggle("自动检测完整内容（仅备忘录 / 文本编辑）", isOn: $preferences.automatic)
                Text("开启后，获得辅助功能授权时会读取当前支持文本框的内容，最多 2000 字；句末停稳后交给本机模型。无法可靠判断所有拼音组合状态，建议先使用手动选区。每次启动默认关闭。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("检查 / 请求辅助功能权限") {
                    assistant.accessibility.requestPermission()
                    permissionMessage = assistant.accessibility.trusted ? "辅助功能已授权。" : "请在系统设置 → 隐私与安全性 → 辅助功能中授权句外。"
                }
                if !permissionMessage.isEmpty { Text(permissionMessage).font(.caption) }
                Text("手动使用“服务 → 使用句外处理”无需全局键盘监听。跨应用只提供复制，不自动替换或发送。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("输入与隐私") {
                Text("直接沿用苹果拼音和 ABC。输入源切换由 macOS 管理，句外不拦截 Caps Lock、地球键、Control–空格或候选词按键。")
                Text("不保存输入历史；原文和结果仅留在运行内存，更新或退出时清除。API 不记录正文日志。输入法的个人词库仍由系统管理。")
            }.font(.caption)
        }
        .formStyle(.grouped).padding(10).frame(minWidth: 530, minHeight: 620)
    }
}
