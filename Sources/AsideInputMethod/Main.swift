import AppKit
import InputMethodKit
import AsideOffline
import AsideCore

@MainActor final class InputMethodDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try RimeEngine.initialize()
            server = IMKServer(name: "AsideInputMethod_Connection", bundleIdentifier: "io.github.pengruoxin.Aside.InputMethod")
        } catch {
            OfflineConfiguration.shared.status = error.localizedDescription
        }
    }
    func applicationWillTerminate(_ notification: Notification) { RuntimeManager.shared.stop() }
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
                guard engine.context.candidates.contains("你好") else { throw SmokeError.noChineseCandidate }
                if let index = engine.context.candidates.firstIndex(of: "你好") { engine.select(index) }
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
