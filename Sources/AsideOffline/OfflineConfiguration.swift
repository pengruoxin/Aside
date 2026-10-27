import Foundation
import Combine
import AsideCore

@MainActor public final class OfflineConfiguration: ObservableObject {
    public static let shared = OfflineConfiguration()
    @Published public var style: ExpressionStyle { didSet { UserDefaults.standard.set(style.rawValue, forKey: "imeStyle") } }
    @Published public var englishOutput: Bool { didSet { UserDefaults.standard.set(englishOutput, forKey: "imeEnglishOutput") } }
    @Published public var automatic: Bool { didSet { UserDefaults.standard.set(automatic, forKey: "imeAutomatic") } }
    @Published public var paused = false
    @Published public var engine: String { didSet { UserDefaults.standard.set(engine, forKey: "imeEngine") } }
    @Published public var status = "离线输入法 · Control–Option–T 处理当前句子"
    @Published public var customModel: String { didSet { UserDefaults.standard.set(customModel, forKey: "imeCustomModel") } }
    private init() {
        style = ExpressionStyle(rawValue: UserDefaults.standard.string(forKey: "imeStyle") ?? "") ?? .casual
        englishOutput = UserDefaults.standard.bool(forKey: "imeEnglishOutput")
        automatic = UserDefaults.standard.object(forKey: "imeAutomatic") as? Bool ?? true
        engine = UserDefaults.standard.string(forKey: "imeEngine") == "apple" ? "apple" : "bundled"
        customModel = UserDefaults.standard.string(forKey: "imeCustomModel") ?? ""
    }
}

public enum OfflinePaths {
    public static var inputMethodBundle: Bundle {
        if Bundle.main.bundleIdentifier == "io.github.pengruoxin.Aside.InputMethod" { return .main }
        if let payload = Bundle.main.url(forResource: "Aside", withExtension: "app"), let bundle = Bundle(url: payload) { return bundle }
        return .main
    }
    public static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aside", isDirectory: true)
    }
    public static var bundledModel: URL? {
        inputMethodBundle.url(forResource: "qwen2.5-1.5b-instruct-q4_k_m", withExtension: "gguf", subdirectory: "Models")
    }
    @MainActor public static var model: URL? {
        let custom = OfflineConfiguration.shared.customModel
        if !custom.isEmpty, FileManager.default.fileExists(atPath: custom) { return URL(fileURLWithPath: custom) }
        return bundledModel
    }
    public static var executable: URL? {
        let url = inputMethodBundle.bundleURL.appendingPathComponent("Contents/Helpers/llama-server")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }
}
