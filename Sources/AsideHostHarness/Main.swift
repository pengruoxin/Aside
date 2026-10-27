import AppKit
import WebKit
import Carbon
import Darwin
import AsideCore
import AsideOffline

/// CI-only host controls. This executable is not included in the installer.
@main enum HostHarness {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        Task { @MainActor in
            do {
                if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--bundle-probe" {
                    try await bundleProbe(URL(fileURLWithPath: CommandLine.arguments[2]))
                } else if CommandLine.arguments.contains("--system-probe") {
                    try await systemProbe()
                } else if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--live" {
                    try await liveInput(URL(fileURLWithPath: CommandLine.arguments[2]))
                } else if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--register" {
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

    @MainActor static func bundleProbe(_ url: URL) async throws {
        guard let identifier = Bundle(url: url)?.bundleIdentifier else { throw Failure.registration }
        let original = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        defer {
            if let original { _ = TISSelectInputSource(original) }
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: identifier) { app.terminate() }
        }
        print("Single-source control registration:", TISRegisterInputSource(url as CFURL))
        let query = [kTISPropertyBundleID as String: identifier] as CFDictionary
        let sources = TISCreateInputSourceList(query, true).takeRetainedValue() as! [TISInputSource]
        for source in sources {
            print("Single-source control enable:", TISEnableInputSource(source))
            print("Single-source control select:", TISSelectInputSource(source))
        }
    }

    @MainActor static func systemProbe() async throws {
        let original = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        defer { if let original { _ = TISSelectInputSource(original) } }
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = editor
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        editor.inputContext?.activate()
        let parentQuery = [kTISPropertyInputSourceID as String: "com.apple.inputmethod.SCIM"] as CFDictionary
        let parents = TISCreateInputSourceList(parentQuery, true).takeRetainedValue() as! [TISInputSource]
        for parent in parents {
            print("Control Apple Pinyin parent enable:", TISEnableInputSource(parent))
            if let raw = TISGetInputSourceProperty(parent, kTISPropertyInputSourceIsEnabled) {
                print("Control Apple Pinyin parent enabled:", CFBooleanGetValue(unsafeBitCast(raw, to: CFBoolean.self)))
            }
        }
        let query = [kTISPropertyInputSourceID as String: "com.apple.inputmethod.SCIM.ITABC"] as CFDictionary
        let sources = TISCreateInputSourceList(query, true).takeRetainedValue() as! [TISInputSource]
        for source in sources {
            print("Control Apple Pinyin enable:", TISEnableInputSource(source))
            print("Control Apple Pinyin select:", TISSelectInputSource(source))
        }
        print("Control Apple Pinyin count:", sources.count)
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
        for _ in 0..<60 {
            if (try? await web.evaluateJavaScript("document.getElementById('search') !== null")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        for field in ["search", "chat"] {
            _ = try await web.evaluateJavaScript("document.getElementById('\(field)').focus()")
            try await Task.sleep(nanoseconds: 300_000_000)
            guard let client = (window.firstResponder as? NSView)?.inputContext?.client else { throw Failure.noTextClient }
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

    @MainActor static func register(_ bundle: URL, enable: Bool = true) async throws {
        print("Registering input method metadata:", bundle.lastPathComponent)
        if enable { try InputSourceRegistration.enableInstalledBundle(bundle) }
        for _ in 0..<10 {
            let query = [kTISPropertyBundleID as String: "io.github.pengruoxin.inputmethod.Aside"] as CFDictionary
            let raw = TISCreateInputSourceList(query, true).takeRetainedValue()
            print("TIS input source count:", CFArrayGetCount(raw))
            let sources = (0..<CFArrayGetCount(raw)).map { unsafeBitCast(CFArrayGetValueAtIndex(raw, $0), to: TISInputSource.self) }
            for source in sources {
                for key in [kTISPropertyInputSourceID, kTISPropertyInputSourceType, kTISPropertyInputModeID] {
                    if let value = TISGetInputSourceProperty(source, key) {
                        print(key, unsafeBitCast(value, to: CFString.self) as String)
                    }
                }
                if let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
                    print("After enable:", CFBooleanGetValue(unsafeBitCast(value, to: CFBoolean.self)))
                }
            }
            let ids = sources.compactMap { input -> String? in
                guard let value = TISGetInputSourceProperty(input, kTISPropertyInputSourceID) else { return nil }
                return unsafeBitCast(value, to: CFString.self) as String
            }
            if ids.contains("io.github.pengruoxin.inputmethod.Aside.Chinese") && ids.contains("io.github.pengruoxin.inputmethod.Aside.English") {
                print("Registered two real TIS input modes:", ids)
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw Failure.registration
    }

    @MainActor static func liveInput(_ bundle: URL) async throws {
        try await register(bundle, enable: false)
        let original = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        defer { if let original { _ = TISSelectInputSource(original) } }
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 130))
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        let delegate = SendDelegate()
        editor.delegate = delegate
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        editor.inputContext?.activate()
        if let original {
            print("Current system input source selection:", TISSelectInputSource(original))
        }
        try await selectMode(".Chinese")
        try await Task.sleep(nanoseconds: 2_000_000_000)
        for char in "nihao" { try await send(String(char), window: window) }
        try await send(" ", window: window)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard editor.string == "你好" else {
            print("Live Chinese value:", editor.string)
            throw Failure.liveChinese
        }
        try await send("\r", window: window)
        guard delegate.submissions == ["你好"] else { throw Failure.returnWasNotForwarded }
        try await selectMode(".English")
        try await Task.sleep(nanoseconds: 500_000_000)
        for char in "Hello." { try await send(String(char), window: window) }
        try await send("\r", window: window)
        guard delegate.submissions == ["你好", "Hello."] else { throw Failure.liveEnglish }
        print("Actual installed IMK source: nihao+Space → 你好; Return submitted once; English mode passed.")
        window.close()
    }
    @MainActor private static func selectMode(_ suffix: String) async throws {
        let query = [kTISPropertyBundleID as String: "io.github.pengruoxin.inputmethod.Aside"] as CFDictionary
        let sources = TISCreateInputSourceList(query, true).takeRetainedValue() as! [TISInputSource]
        for source in sources {
            if let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
               (unsafeBitCast(value, to: CFString.self) as String).hasSuffix(suffix) {
                let status = TISSelectInputSource(source)
                print("Select mode", suffix, "status:", status)
                if let enabled = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) {
                    print("Enabled:", CFBooleanGetValue(unsafeBitCast(enabled, to: CFBoolean.self)))
                }
                if let selectable = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) {
                    print("Selectable:", CFBooleanGetValue(unsafeBitCast(selectable, to: CFBoolean.self)))
                }
                guard status == noErr else { throw Failure.registration }
                return
            }
        }
        throw Failure.registration
    }
    @MainActor private static func send(_ text: String, window: NSWindow) async throws {
        let codes: [String: UInt16] = ["a":0, "s":1, "d":2, "f":3, "h":4, "g":5, "z":6, "x":7, "c":8, "v":9,
            "b":11, "q":12, "w":13, "e":14, "r":15, "y":16, "t":17, "o":31, "u":32, "i":34, "p":35,
            "l":37, "j":38, "k":40, "n":45, "m":46, ".":47, " ":49, "\r":36]
        let uppercase = text != text.lowercased()
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: uppercase ? .shift : [],
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                    context: nil, characters: text, charactersIgnoringModifiers: text.lowercased(),
                                    isARepeat: false, keyCode: codes[text.lowercased()] ?? 0)!
        NSApp.sendEvent(event)
        try await Task.sleep(nanoseconds: 80_000_000)
    }
    @MainActor private final class SendDelegate: NSObject, NSTextViewDelegate {
        var submissions: [String] = []
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                submissions.append(textView.string)
                textView.string = ""
                return true
            }
            return false
        }
    }
    enum Failure: Error { case previewLeaked, noTextClient, registration, liveChinese, liveEnglish, returnWasNotForwarded }
}
