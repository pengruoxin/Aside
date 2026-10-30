import AppKit
import InputMethodKit
import AsideOffline
import AsideCore

func imeDiagnostic(_ message: String) {
    guard let path = ProcessInfo.processInfo.environment["ASIDE_IMK_DIAGNOSTICS_PATH"] else { return }
    let url = URL(fileURLWithPath: path)
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    guard let file = try? FileHandle(forWritingTo: url) else { return }
    defer { try? file.close() }
    _ = try? file.seekToEnd()
    try? file.write(contentsOf: Data((message + "\n").utf8))
}

@MainActor final class InputMethodDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?
    private var diagnosticMouseMonitor: Any?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.environment["ASIDE_IMK_DIAGNOSTICS_PATH"] != nil {
            diagnosticMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
                imeDiagnostic("local candidate mouse event: \(event.type.rawValue); window: \(event.windowNumber)")
                return event
            }
        }
        imeDiagnostic("application launched; controller available: \(NSClassFromString("AsideInputController") != nil)")
        NSLog("Aside input method starting; controller available: %@", NSClassFromString("AsideInputController") == nil ? "no" : "yes")
        fputs("Aside applicationDidFinishLaunching; controller available: \(NSClassFromString("AsideInputController") != nil)\n", stderr)
        do {
            try RimeEngine.initialize()
            _ = InputController.self
            guard let identifier = Bundle.main.bundleIdentifier,
                  let connection = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String else {
                throw SmokeError.invalidMetadata
            }
            server = IMKServer(name: connection, bundleIdentifier: identifier)
            imeDiagnostic("server initialized: \(server != nil)")
            NSLog("Aside input method server initialized: %@", server == nil ? "no" : "yes")
            fputs("Aside server initialized: \(server != nil)\n", stderr)
        } catch {
            OfflineConfiguration.shared.status = error.localizedDescription
        }
    }
    func applicationWillTerminate(_ notification: Notification) { RuntimeManager.shared.stop() }
    private enum SmokeError: Error { case invalidMetadata }
}

@main enum InputMethodMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--rime-build"), arguments.count >= 4 {
            do {
                try RimeEngine.initialize(data: URL(fileURLWithPath: arguments[2]), user: URL(fileURLWithPath: arguments[3]))
                exit(0)
            } catch { fputs("\(error)\n", stderr); exit(1) }
        }
        if arguments.contains("--engine-smoke-test") {
            do {
                try RimeEngine.initialize()
                let engine = RimeEngine()
                for scalar in "nihao".unicodeScalars { _ = engine.process(Int32(scalar.value)) }
                print("Fixture preedit: \(engine.context.preedit); candidates: \(engine.context.candidates)")
                guard engine.context.candidates.contains("你好") else { throw SmokeError.noChineseCandidate }
                if let index = engine.context.candidates.firstIndex(of: "你好") { engine.select(index) }
                guard engine.takeCommit() == "你好" else { throw SmokeError.wrongCommit }
                for scalar in "nihao".unicodeScalars { _ = engine.process(Int32(scalar.value)) }
                engine.commit()
                guard engine.takeCommit() == "你好" else { throw SmokeError.wrongCommit }
                print("Rime nihao → 你好 passed; source and preview isolation covered by Swift tests.")
                exit(0)
            } catch { fputs("Engine smoke failed: \(error)\n", stderr); exit(1) }
        }
        if arguments.contains("--offline-smoke-test") {
            let app = NSApplication.shared
            Task { @MainActor in
                do {
                    OfflineConfiguration.shared.engine = "bundled"
                    for source in ["我们可以先试一下。", "This method could work."] {
                        let result = try await OfflineTranslator.generate(.init(source: source, style: .academic))
                        print("Offline fixture expression:", result.expression)
                        print("Offline fixture explanation:", result.explanation)
                        guard SentencePolicy.language(of: result.expression) == .english,
                              SentencePolicy.language(of: result.explanation) == .chinese else { throw SmokeError.invalidOfflineOutput }
                        print("Offline \(SentencePolicy.language(of: source).rawValue) translation/rewrite and Chinese explanation passed.")
                    }
                    RuntimeManager.shared.stop()
                    exit(0)
                } catch { RuntimeManager.shared.stop(); fputs("Offline smoke failed: \(error)\n", stderr); exit(1) }
            }
            app.run()
            return
        }
        let app = NSApplication.shared
        let delegate = InputMethodDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    enum SmokeError: Error { case noChineseCandidate, wrongCommit, invalidOfflineOutput }
}
