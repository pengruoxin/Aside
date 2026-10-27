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
                        Button("收藏") { assistant.saveResult() }
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                BrandMark()
                Text("句外 Aside").font(.title2.weight(.semibold))
                Spacer()
                Text(preferences.style.title).font(.caption).foregroundStyle(.secondary)
            }
            Text("中文照常写，英文顺手学。").foregroundStyle(.secondary)
            if preferences.needsSetup {
                HStack {
                    Label("先连接你的翻译服务", systemImage: "wand.and.stars")
                    Spacer()
                    Button("去设置") { openWindow(id: "preferences") }
                }.padding(12).background(AsideTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }
            Picker("英文风格", selection: $preferences.style) {
                ForEach(ExpressionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).frame(width: 230)
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
                if !assistant.draft.isEmpty { Button("清空") { assistant.clearContent() } }
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
        .padding(26).frame(minWidth: 550, minHeight: 470).tint(AsideTheme.accent)
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
        }.padding(18).frame(width: 370).tint(AsideTheme.accent)
    }
}
