import Foundation
import RimeBridge
import AsideOffline

final class RimeEngine {
    struct Context {
        var preedit = ""
        var cursor = 0
        var candidates: [String] = []
    }
    private static var initialized = false
    private var session: UInt = 0

    static func initialize(data: URL? = nil, user: URL? = nil) throws {
        if initialized { return }
        let data = data ?? Bundle.main.resourceURL!.appendingPathComponent("RimeData", isDirectory: true)
        let user = user ?? OfflinePaths.support.appendingPathComponent("Rime", isDirectory: true)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        guard aside_rime_initialize(data.path, user.path, data.appendingPathComponent("build").path) != 0 else {
            throw NSError(domain: "Aside.Rime", code: 1, userInfo: [NSLocalizedDescriptionKey: "拼音引擎未能初始化。"])
        }
        initialized = true
    }
    init() { session = aside_rime_create() }
    deinit { aside_rime_destroy(session) }
    var available: Bool { session != 0 }
    func process(_ key: Int32, modifiers: Int32 = 0) -> Bool { aside_rime_process(session, key, modifiers) != 0 }
    func select(_ index: Int) { _ = aside_rime_select(session, index) }
    func clear() { aside_rime_clear(session) }
    func commit() { aside_rime_commit(session) }
    func takeCommit() -> String? {
        guard let pointer = aside_rime_take_commit(session) else { return nil }
        defer { aside_rime_free_string(pointer) }
        return Self.simplified(String(cString: pointer))
    }
    var context: Context {
        var value = AsideRimeContext()
        guard aside_rime_context(session, &value) != 0 else { return Context() }
        defer { aside_rime_free_context(&value) }
        var output = Context()
        output.preedit = value.preedit.map { String(cString: $0) } ?? ""
        output.cursor = Int(value.cursor)
        for i in 0..<Int(value.count) {
            if let candidate = value.candidates?[i] { output.candidates.append(Self.simplified(String(cString: candidate))) }
        }
        return output
    }
    static func simplified(_ text: String) -> String {
        text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
    }
}
