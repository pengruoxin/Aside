import SwiftUI
import AppKit
import Carbon
import AsideOffline
import AsideCore

@MainActor final class Installation: ObservableObject {
    @Published var busy = false
    @Published var message = "安装到当前用户的输入法目录，无需管理员密码。"
    @Published var installed = false
    func install() {
        guard !busy else { return }
        busy = true
        message = "正在安装输入法与离线语言包，请稍候…"
        Task { @MainActor in
            do {
                guard let source = Bundle.main.url(forResource: "Aside", withExtension: "app") else { throw InstallError.payloadMissing }
                let parent = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods", isDirectory: true)
                let destination = parent.appendingPathComponent("Aside.app")
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
                   let value = TISGetInputSourceProperty(current, kTISPropertyBundleID),
                   (unsafeBitCast(value, to: CFString.self) as String) == "io.github.pengruoxin.inputmethod.Aside" {
                    throw InstallError.inputMethodActive
                }
                let backupRoot = OfflinePaths.support.appendingPathComponent("Backups", isDirectory: true)
                let backup = try await Task.detached(priority: .userInitiated) {
                    try InstallTransaction.install(source: source, destination: destination, backupRoot: backupRoot,
                                                   identifier: "io.github.pengruoxin.inputmethod.Aside", validate: { staged in
                        let check = Process()
                        check.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                        check.arguments = ["--verify", "--deep", "--strict", staged.path]
                        check.standardOutput = FileHandle.nullDevice
                        check.standardError = FileHandle.nullDevice
                        try check.run()
                        check.waitUntilExit()
                        if check.terminationStatus != 0 { throw InstallError.invalidSignature }
                    })
                }.value
                let requiresLogin = try InputSourceRegistration.enableInstalledBundle(destination)
                installed = true
                message = requiresLogin
                    ? "文件已安装，需要重新登录完成启用。请先保存工作，退出登录后重新登录，再在菜单栏输入源中选择“句外拼音”或“句外英文”。"
                    : backup == nil
                    ? "安装完成。请在菜单栏输入源中选择“句外拼音”或“句外英文”。若暂未出现，请退出登录后重新登录，再在键盘设置添加。"
                    : "升级完成，旧版已备份。请先退出登录并重新登录，让 macOS 加载新版本，再切换到句外输入法。"
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
    enum InstallError: LocalizedError {
        case payloadMissing, otherApplication, registrationFailed, inputMethodActive, invalidSignature
        var errorDescription: String? {
            switch self {
            case .payloadMissing: return "安装包不完整，请重新下载完整版 DMG。"
            case .otherApplication: return "目标位置存在其他应用，未作覆盖。请手动检查 ~/Library/Input Methods/Aside.app。"
            case .registrationFailed: return "输入法已复制，请退出登录后重新登录，并在系统设置 → 键盘 → 文本输入 → 编辑中添加句外。"
            case .inputMethodActive: return "请先用系统输入源菜单切换到 ABC 或苹果拼音，再重新安装句外。"
            case .invalidSignature: return "输入法包的完整性检查未通过，原有输入法未被替换。请重新下载。"
            }
        }
    }
}

struct InstallerView: View {
    @StateObject private var installation = Installation()
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("句外输入法").font(.largeTitle.weight(.semibold))
            Text("就在搜索框、聊天框里，学会另一种表达。").font(.title3).foregroundStyle(.secondary)
            Label("原生拼音与英文输入源", systemImage: "keyboard")
            Label("包内离线模型 · 不需要 API Key 或 Ollama", systemImage: "internaldrive")
            Label("不自动发送，不把学习提示混入正文", systemImage: "checkmark.shield")
            Divider()
            Text("安装后使用 macOS 输入源菜单切换。空格与数字选词；Return 先确认组合，再交给百度搜索或微信发送。句末给出英文候选，无标点时按 Control–Option–T。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(installation.message).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if installation.busy { ProgressView().controlSize(.small) }
            HStack {
                Button("离线模型与设置…") { SettingsWindow.shared.show() }
                Spacer()
                Button(installation.installed ? "重新安装" : "安装句外输入法") { installation.install() }
                    .buttonStyle(.borderedProminent).disabled(installation.busy)
            }
            Text("适用于 Apple Silicon / macOS 26+ · 0.3.0 输入法测试版\n未完成 Apple Developer ID 签名与公证。实际百度、微信兼容性仍需验收。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(32).frame(width: 590).tint(Color(red: 0.30, green: 0.42, blue: 0.34))
            .onAppear { InstallerScreenshots.runIfRequested(); InstallerSmoke.runIfRequested() }
    }
}

@main struct InstallerApp: App {
    var body: some Scene {
        Window("安装句外输入法", id: "installer") { InstallerView() }.windowResizability(.contentSize)
    }
}
