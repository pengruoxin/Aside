import AppKit
import WebKit
import Carbon
import AsideCore

/// CI-only host controls. This executable is not included in the installer.
@main enum HostHarness {
    @MainActor static func main() {
        let app = NSApplication.shared
        Task { @MainActor in
            do {
                if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--register" {
                    try await register(URL(fileURLWithPath: CommandLine.arguments[2]))
                } else {
                    try await nativeText()
                    try await webText()
                }
                print("Input host controls passed. These fixtures are NOT real Baidu/WeChat acceptance.")
                exit(0)
            } catch { fputs("Host test failed: \(error)\n", stderr); exit(1) }
        }
        app.run()
    }

    @MainActor static func nativeText() async throws {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 100))
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        var state = SentenceComposition()
        state.append("你好。")
        _ = state.acceptPreview(try .validated(expression: "Hello.", explanation: "问候。"), revision: state.revision)
        editor.setMarkedText(state.hostMarkedText(preedit: ""), selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.insertText(state.takeOriginal(), replacementRange: NSRange(location: NSNotFound, length: 0))
        guard editor.string == "你好。", !editor.string.contains("Hello") else { throw Failure.previewLeaked }
        window.close()
    }

    @MainActor static func webText() async throws {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        web.loadHTMLString("<html><body><input id='search' type='search'><textarea id='chat'></textarea></body></html>", baseURL: nil)
        for _ in 0..<30 {
            if (try? await web.evaluateJavaScript("document.readyState")) as? String == "complete" { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        for field in ["search", "chat"] {
            _ = try await web.evaluateJavaScript("document.getElementById('\(field)').focus()")
            try await Task.sleep(nanoseconds: 300_000_000)
            guard let client = window.firstResponder?.inputContext?.client else { throw Failure.noTextClient }
            var state = SentenceComposition()
            state.append("我们可以先试一下。")
            _ = state.acceptPreview(try .validated(expression: "We could try it first.", explanation: "先尝试。"), revision: state.revision)
            let text = state.hostMarkedText(preedit: "")
            client.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            client.insertText(state.takeOriginal(), replacementRange: NSRange(location: NSNotFound, length: 0))
            try await Task.sleep(nanoseconds: 200_000_000)
            let value = try await web.evaluateJavaScript("document.getElementById('\(field)').value") as? String
            guard value == text else { throw Failure.previewLeaked }
        }
        window.close()
    }

    @MainActor static func register(_ bundle: URL) async throws {
        guard TISRegisterInputSource(bundle as CFURL) == noErr else { throw Failure.registration }
        for _ in 0..<10 {
            let query = [kTISPropertyBundleID as String: "io.github.pengruoxin.Aside.InputMethod"] as CFDictionary
            let sources = TISCreateInputSourceList(query, true).takeRetainedValue() as! [TISInputSource]
            let ids = sources.compactMap { input -> String? in
                guard let value = TISGetInputSourceProperty(input, kTISPropertyInputSourceID) else { return nil }
                return unsafeBitCast(value, to: CFString.self) as String
            }
            if ids.contains("io.github.pengruoxin.Aside.InputMethod.Chinese") && ids.contains("io.github.pengruoxin.Aside.InputMethod.English") {
                print("Registered two real TIS input modes:", ids)
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw Failure.registration
    }
    enum Failure: Error { case previewLeaked, noTextClient, registration }
}
