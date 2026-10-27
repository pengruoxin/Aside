import SwiftUI
import AsideCore

enum AsideTheme {
    static let accent = Color(red: 0.32, green: 0.43, blue: 0.35)
}

struct BrandMark: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: size * 0.25).fill(AsideTheme.accent)
            Text("a").font(.custom("Georgia-Italic", size: size * 0.88)).foregroundStyle(.white)
                .frame(width: size, height: size).offset(y: -1)
            Circle().fill(Color(red: 0.81, green: 0.87, blue: 0.68))
                .frame(width: size * 0.11, height: size * 0.11).padding(size * 0.17)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ServiceSetupView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var assistant: AssistantModel
    @State private var key = ""
    @State private var models: [String] = []
    @State private var status = ""
    @State private var checking = false
    @State private var work: Task<Void, Never>?
    @State private var token = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("翻译服务", selection: $preferences.backend) {
                Text("本机 Ollama").tag("local")
                Text("云端 API").tag("cloud")
            }.pickerStyle(.segmented)
            if preferences.backend == "local" {
                Label("文字仅交给本机运行的模型", systemImage: "desktopcomputer")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    TextField("已安装的模型名", text: $preferences.model)
                    Button("检测本机模型") { detectModels() }.disabled(checking)
                }
                if !models.isEmpty {
                    Picker("选择已检测到的模型", selection: $preferences.model) {
                        if !models.contains(preferences.model) { Text(preferences.model.isEmpty ? "请选择" : preferences.model).tag(preferences.model) }
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                }
                Text("需先安装并启动 Ollama，下载你选择的中英双语模型。句外不会自行下载大模型。")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Ollama 安装说明 ↗", destination: URL(string: "https://ollama.com/download/mac")!)
            } else {
                TextField("HTTPS API 基础地址", text: $preferences.baseURL)
                    .help("例如 https://api.openai.com/v1；兼容 Chat Completions JSON 模式")
                TextField("模型名", text: $preferences.cloudModel, prompt: Text("填写你的服务支持的模型"))
                HStack {
                    SecureField("API Key（不会回显）", text: $key)
                    Button("保存密钥") {
                        do {
                            _ = try AsideCore.CloudEndpoint.url(base: preferences.baseURL)
                            try KeychainStore.save(key.trimmingCharacters(in: .whitespacesAndNewlines), endpoint: preferences.baseURL)
                            key = ""
                            status = "密钥已存入 Mac 钥匙串。"
                        } catch { status = error.localizedDescription }
                    }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("移除") {
                        do { try KeychainStore.save("", endpoint: preferences.baseURL); key = ""; status = "此地址的密钥已移除。" }
                        catch { status = error.localizedDescription }
                    }
                }
                Toggle("允许把当前句子发送到此服务（本次运行）", isOn: $preferences.cloudConsent)
                Text("接收地址：\(preferences.baseURL)\n只发送你选中或主动处理的内容及表达要求。云端可能收费，数据规则以服务提供商为准。")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            HStack(spacing: 10) {
                Button("测试翻译连接") { testService() }.disabled(checking || preferences.needsSetup)
                if checking { ProgressView().controlSize(.small) }
            }
            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onChange(of: preferences.backend + preferences.baseURL + preferences.model + preferences.cloudModel) { _ in
            token = UUID(); work?.cancel(); checking = false; status = ""; key = ""
        }
        .onDisappear { work?.cancel() }
    }

    private func detectModels() {
        checking = true; status = "正在连接本机 Ollama…"
        let current = UUID(); token = current
        work = Task { @MainActor in
            do {
                let found = try await WritingService().localModels()
                guard !Task.isCancelled, token == current else { return }
                models = found
                status = found.isEmpty ? "服务已连接，但未安装模型。请先在 Ollama 安装模型。" : "已找到 \(found.count) 个模型，请选择一个。"
            } catch {
                guard !Task.isCancelled, token == current else { return }
                status = "未连接到本机 Ollama，请确认服务已启动。"
            }
            checking = false
        }
    }

    private func testService() {
        checking = true; status = "正在用固定示例“你好。”测试，不发送编辑区内容…"
        let current = UUID(); token = current
        let configuration = assistant.serviceConfiguration()
        work = Task { @MainActor in
            do {
                let output = try await WritingService().generate(.init(source: "你好。", style: preferences.style), configuration: configuration)
                guard !Task.isCancelled, token == current else { return }
                status = "连接成功 · \(output.expression)"
            } catch {
                guard !Task.isCancelled, token == current else { return }
                status = error.localizedDescription
            }
            checking = false
        }
    }
}
