import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AsideCore

@MainActor public final class SettingsWindow {
    public static let shared = SettingsWindow()
    private var window: NSWindow?
    private init() {}
    public func show() {
        if window == nil {
            let view = OfflineSettingsView()
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 610), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "句外输入法设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view)
            self.window = window
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

public struct OfflineSettingsView: View {
    @ObservedObject private var settings = OfflineConfiguration.shared
    @State private var testing = false
    @State private var result = ""
    public init() {}
    public var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text("a·").font(.custom("Georgia-Italic", size: 32)).foregroundStyle(.white)
                        .frame(width: 46, height: 46).background(Color(red: 0.30, green: 0.42, blue: 0.34), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("句外输入法").font(.title2.weight(.semibold))
                        Text("在正在打字的地方，学会另一种表达。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("输入与表达") {
                Picker("英文风格", selection: $settings.style) {
                    ForEach(ExpressionStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("使用方式", selection: $settings.englishOutput) {
                    Text("学习对照").tag(false)
                    Text("英文输出").tag(true)
                }.pickerStyle(.segmented)
                Toggle("写完一句自动给出英文候选", isOn: $settings.automatic)
                Toggle("暂停学习提示（打字仍可用）", isOn: $settings.paused)
                Text("无标点时按 Control–Option–T 主动处理。学习模式点击英文候选看讲解；英文输出模式按 Tab 或点候选采用英文。Return 不会自动采用英文。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("完全本机处理") {
                Picker("离线引擎", selection: $settings.engine) {
                    Text("句外包内语言模型").tag("bundled")
                    Text("苹果本机模型（需 Apple Intelligence 可用）").tag("apple")
                }
                Label(OfflinePaths.model == nil ? "未找到句外离线语言包" : "句外离线语言包已就绪", systemImage: OfflinePaths.model == nil ? "exclamationmark.circle" : "checkmark.circle")
                Text(OfflineTranslator.appleAvailable ? "苹果本机模型可用。" : "苹果本机模型当前不可用；包内模型不依赖它。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("测试离线翻译") {
                        testing = true; result = "正在本机加载模型；中文输入不会等待它。"
                        Task { @MainActor in
                            do {
                                let output = try await OfflineTranslator.generate(.init(source: "我们可以先试一下。", style: settings.style))
                                result = output.expression + "\n" + output.explanation
                            } catch { result = error.localizedDescription }
                            testing = false
                        }
                    }.disabled(testing)
                    Button("导入 GGUF…") { importModel() }
                    if testing { ProgressView().controlSize(.small) }
                }
                if !result.isEmpty { Text(result).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                Text("无 API Key，无云端服务。包内模型约 1.1GB，首次加载可能需要数秒，空闲三分钟后释放。模型可用不等于译文完全准确。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("正常搜索与聊天") {
                Text("句外拼音与句外英文作为系统输入源切换。空格 / 数字选词；Return 先确认拼音，再交还应用执行搜索或发送。Cmd、Option 等系统编辑快捷键保持交给应用。")
                Text("译文只显示在原生候选区，不混入正文。百度、微信的最终表现需实机验证；不支持的控件仍保留原文输入。")
                Text(settings.status).foregroundStyle(.secondary)
            }.font(.caption)
        }
        .formStyle(.grouped).frame(minWidth: 570, minHeight: 600)
        .tint(Color(red: 0.30, green: 0.42, blue: 0.34))
    }
    private func importModel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "gguf") ?? .data]
        panel.message = "选择可信来源的 GGUF 离线模型。文件将在本机读取，不会上传。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            guard try file.read(upToCount: 4) == Data("GGUF".utf8) else {
                result = "所选文件不是有效 GGUF 文件。"; return
            }
        } catch { result = error.localizedDescription; return }
        settings.customModel = url.path
        RuntimeManager.shared.stop()
        result = "已选择本机模型；请测试是否与推理引擎兼容。"
    }
}
