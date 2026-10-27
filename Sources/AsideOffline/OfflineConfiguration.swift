import Foundation
import Combine
import AsideCore

@MainActor public final class OfflineConfiguration: ObservableObject {
    public static let shared = OfflineConfiguration()
    private static let store = UserDefaults(suiteName: "io.github.pengruoxin.Aside.Shared")!
    @Published public var style: ExpressionStyle { didSet { Self.store.set(style.rawValue, forKey: "imeStyle"); Self.changed() } }
    @Published public var englishOutput: Bool { didSet { Self.store.set(englishOutput, forKey: "imeEnglishOutput"); Self.changed() } }
    @Published public var automatic: Bool { didSet { Self.store.set(automatic, forKey: "imeAutomatic"); Self.changed() } }
    @Published public var paused: Bool { didSet { Self.store.set(paused, forKey: "imePaused"); Self.changed() } }
    @Published public var engine: String { didSet {
        if engine != oldValue { RuntimeManager.shared.stop() }
        Self.store.set(engine, forKey: "imeEngine"); Self.changed()
    } }
    @Published public var status = "离线输入法 · Control–Option–T 处理当前句子"
    @Published public var customModel: String { didSet {
        if customModel != oldValue { RuntimeManager.shared.stop() }
        Self.store.set(customModel, forKey: "imeCustomModel"); Self.changed()
    } }
    private var observer: NSObjectProtocol?
    public static let notification = Notification.Name("io.github.pengruoxin.Aside.PreferencesChanged")
    private static func changed() {
        store.synchronize()
        DistributedNotificationCenter.default().postNotificationName(notification, object: nil, userInfo: nil, deliverImmediately: true)
    }
    private func reload() {
        Self.store.synchronize()
        let nextStyle = ExpressionStyle(rawValue: Self.store.string(forKey: "imeStyle") ?? "") ?? .casual
        if style != nextStyle { style = nextStyle }
        let nextOutput = Self.store.bool(forKey: "imeEnglishOutput")
        if englishOutput != nextOutput { englishOutput = nextOutput }
        let nextAuto = Self.store.object(forKey: "imeAutomatic") as? Bool ?? true
        if automatic != nextAuto { automatic = nextAuto }
        let nextPaused = Self.store.bool(forKey: "imePaused")
        if paused != nextPaused { paused = nextPaused }
        let nextEngine = Self.store.string(forKey: "imeEngine") == "apple" ? "apple" : "bundled"
        if engine != nextEngine { engine = nextEngine }
        let nextModel = Self.store.string(forKey: "imeCustomModel") ?? ""
        if customModel != nextModel { customModel = nextModel }
    }
    private init() {
        paused = Self.store.bool(forKey: "imePaused")
        style = ExpressionStyle(rawValue: Self.store.string(forKey: "imeStyle") ?? "") ?? .casual
        englishOutput = Self.store.bool(forKey: "imeEnglishOutput")
        automatic = Self.store.object(forKey: "imeAutomatic") as? Bool ?? true
        engine = Self.store.string(forKey: "imeEngine") == "apple" ? "apple" : "bundled"
        customModel = Self.store.string(forKey: "imeCustomModel") ?? ""
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.notification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }
}

public enum OfflinePaths {
    public static var inputMethodBundle: Bundle {
        if Bundle.main.bundleIdentifier == "io.github.pengruoxin.inputmethod.Aside" { return .main }
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
