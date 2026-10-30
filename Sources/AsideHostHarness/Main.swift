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
        print("Harness activation policy before setup:", app.activationPolicy().rawValue)
        print("Event posting permission:", CGPreflightPostEventAccess())
        app.setActivationPolicy(.regular)
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
            try await Task.sleep(nanoseconds: 2_000_000_000)
            for character in "nihao " { try await send(String(character), window: window) }
            print("Control Apple Pinyin typed value:", editor.string)
            guard editor.string == "你好" else { throw Failure.systemControl }
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
            let text = state.source
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
        window.title = "句外输入法 · 标准输入框验证"
        window.center()
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
        let installedPath = bundle.resolvingSymlinksInPath().path
        guard NSRunningApplication.runningApplications(withBundleIdentifier: InputSourcePreferences.bundleID).contains(where: {
            $0.bundleURL?.resolvingSymlinksInPath().path == installedPath
        }) else { throw Failure.wrongInstalledBundle }
        print("Host active:", NSApp.isActive, "key window:", window.isKeyWindow,
              "input context:", editor.inputContext?.selectedKeyboardInputSource ?? "nil")
        for char in "nihao" { try await send(String(char), window: window) }
        try await HostSnapshot.capture("pinyin-candidates", host: window)
        try await send(" ", window: window)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard editor.string == "你好", !editor.hasMarkedText() else {
            print("Live Chinese value:", editor.string)
            throw Failure.liveChinese
        }
        for char in "nihao " { try await send(String(char), window: window) }
        guard editor.string == "你好你好", !editor.hasMarkedText() else { throw Failure.liveChinese }
        try await send("\u{8}", window: window)
        guard editor.string == "你好你" else { throw Failure.liveChinese }
        try await send("\u{8}", window: window)
        guard editor.string == "你好" else { throw Failure.liveChinese }
        print("Confirmed words accumulated without marked text; native Backspace deleted normally.")
        try await send("\r", window: window)
        guard delegate.submissions == ["你好"] else { throw Failure.returnWasNotForwarded }
        try await selectMode(".English")
        try await Task.sleep(nanoseconds: 500_000_000)
        for char in "Hello." { try await send(String(char), window: window) }
        try await send("\r", window: window)
        guard delegate.submissions == ["你好", "Hello."] else { throw Failure.liveEnglish }
        editor.string = "Keep this selection."
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.utf16.count))
        let oldStyle = OfflineConfiguration.shared.style
        OfflineConfiguration.shared.style = oldStyle == .casual ? .academic : .casual
        try await Task.sleep(nanoseconds: 400_000_000)
        guard editor.string == "Keep this selection." else { throw Failure.hostSelectionChanged }
        OfflineConfiguration.shared.style = oldStyle
        try await Task.sleep(nanoseconds: 200_000_000)
        guard editor.string == "Keep this selection." else { throw Failure.hostSelectionChanged }
        editor.string = ""
        print("Style changes preserved host-selected text outside the IME composition.")
        print("Actual installed IMK source: nihao+Space → 你好; Return submitted once; English mode passed.")
        if CommandLine.arguments.contains("--offline-input") {
            try await offlineInput(editor: editor, window: window, delegate: delegate)
        }
        window.close()
        try await liveWebInput()
        try await liveBaidu()
    }

    @MainActor private static func liveBaidu() async throws {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        let observer = BaiduNavigation()
        web.navigationDelegate = observer
        web.uiDelegate = observer
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "句外输入法 · 百度实际页面验证"
        window.contentView = web
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        web.load(URLRequest(url: URL(string: "https://www.baidu.com/")!))
        let focus = "(() => { const field=[...document.querySelectorAll('#chat-textarea,#kw,input[name=wd],textarea[name=wd]')].find(f=>{const r=f.getBoundingClientRect();return r.width>0&&r.height>0&&getComputedStyle(f).visibility!=='hidden';}); if(!field)return false; window.asideProbeField=field;field.value='';field.focus();return document.activeElement===field; })()"
        var loaded = false
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript(focus)) as? Bool == true { loaded = true; break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard loaded else {
            try baiduReport("UNAVAILABLE: runner could not load the real Baidu search field; no Baidu acceptance claim.")
            return
        }
        try await selectMode(".Chinese")
        try await Task.sleep(nanoseconds: 700_000_000)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        _ = try await web.evaluateJavaScript(focus)
        try await clickWebField(web, window: window)
        web.inputContext?.activate()
        web.inputContext?.selectedKeyboardInputSource = InputSourcePreferences.bundleID + ".Chinese"
        try await selectMode(".Chinese")
        try await Task.sleep(nanoseconds: 500_000_000)
        print("Baidu native focus:", NSApp.isActive, window.isKeyWindow, String(describing: window.firstResponder))
        _ = try await web.evaluateJavaScript("window.asideKeys=[];for(const name of ['keydown','keyup','compositionstart','compositionend'])document.addEventListener(name,e=>asideKeys.push([e.type,e.key,e.keyCode,e.isComposing]),true)")
        print("Baidu focused element:", try await web.evaluateJavaScript("document.activeElement.tagName+'#'+document.activeElement.id"))
        for character in "nihao " { try await send(String(character), window: window) }
        let value = try await web.evaluateJavaScript("document.activeElement.value") as? String
        print("Baidu fixture value:", value ?? "nil")
        print("Baidu event trace after typing:", try await web.evaluateJavaScript("JSON.stringify(window.asideKeys)"))
        print("Baidu context source:", web.inputContext?.selectedKeyboardInputSource ?? "nil")
        try await HostSnapshot.capture("baidu-input", host: window)
        if value == "你好" { try await send("\r", window: window) }
        for _ in 0..<40 {
            if observer.searches > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if value != "你好" || observer.searches != 1 {
            print("Baidu Aside event diagnostics:", try await web.evaluateJavaScript("JSON.stringify(window.asideKeys)"))
            let query = [kTISPropertyInputSourceID as String: "com.apple.inputmethod.SCIM.ITABC"] as CFDictionary
            let sources = TISCreateInputSourceList(query, true).takeRetainedValue() as! [TISInputSource]
            guard let apple = sources.first, TISSelectInputSource(apple) == noErr else { throw Failure.liveBaidu }
            _ = try await web.evaluateJavaScript(focus)
            try await clickWebField(web, window: window)
            _ = try await web.evaluateJavaScript("window.asideKeys=[]")
            try await Task.sleep(nanoseconds: 700_000_000)
            for character in "nihao " { try await send(String(character), window: window) }
            print("Baidu Apple control typed value:", try await web.evaluateJavaScript("document.activeElement.value"))
            try await send("\r", window: window)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            print("Baidu Apple event diagnostics:", try await web.evaluateJavaScript("JSON.stringify(window.asideKeys)"))
            print("Baidu Apple control observed searches:", observer.searches)
            throw Failure.liveBaidu
        }
        try baiduReport("PASS: actual https://www.baidu.com/ in WebKit accepted IMK Chinese input and one Return search for 你好. Navigation was cancelled after observing the search request.")
    }

    private static func baiduReport(_ message: String) throws {
        print(message)
        if let folder = ProcessInfo.processInfo.environment["ASIDE_SMOKE_OUTPUT"] {
            try Data(message.utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent("baidu.txt"))
        }
    }

    @MainActor private static func clickWebField(_ web: WKWebView, window: NSWindow) async throws {
        let point = try await web.evaluateJavaScript("(() => {const r=window.asideProbeField.getBoundingClientRect();return [r.x+r.width/2,r.y+r.height/2];})()") as? [Double]
        guard let point, point.count == 2 else { throw Failure.liveBaidu }
        let local = NSPoint(x: point[0], y: web.isFlipped ? point[1] : web.bounds.height - point[1])
        let screen = window.convertPoint(toScreen: web.convert(local, to: nil))
        let location = CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screen.y)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location, mouseButton: .left)!
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.postToPid(getpid())
            try await Task.sleep(nanoseconds: 60_000_000)
        }
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    @MainActor private final class BaiduNavigation: NSObject, WKNavigationDelegate, WKUIDelegate {
        var searches = 0
        private func search(_ url: URL?) -> Bool {
            guard let url else { return false }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { ["wd", "word", "q", "query"].contains($0.name) && $0.value == "你好" }) == true
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if search(navigationAction.request.url) { searches += 1 }
            return nil
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if search(navigationAction.request.url) {
                searches += 1
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }

    @MainActor private static func offlineInput(editor: NSTextView, window: NSWindow, delegate: SendDelegate) async throws {
        let settings = OfflineConfiguration.shared
        let previous = (settings.engine, settings.style, settings.automatic, settings.englishOutput, settings.paused, settings.customModel)
        defer {
            settings.engine = previous.0; settings.style = previous.1; settings.automatic = previous.2
            settings.englishOutput = previous.3; settings.paused = previous.4; settings.customModel = previous.5
        }
        settings.engine = "bundled"; settings.style = .casual; settings.automatic = false
        settings.englishOutput = false; settings.paused = false; settings.customModel = ""
        try await selectMode(".Chinese")
        try await Task.sleep(nanoseconds: 700_000_000)
        for character in "nihao " { try await send(String(character), window: window) }
        guard editor.string == "你好", let path = ProcessInfo.processInfo.environment["ASIDE_IMK_DIAGNOSTICS_PATH"] else { throw Failure.liveChinese }
        func readyCount() -> Int { ((try? String(contentsOfFile: path)) ?? "").components(separatedBy: "preview ready").count }
        let before = readyCount()
        try await send("t", window: window, modifiers: [.maskControl, .maskAlternate])
        let deadline = ProcessInfo.processInfo.systemUptime + 240
        while readyCount() == before, ProcessInfo.processInfo.systemUptime < deadline {
            guard editor.string == "你好" else { throw Failure.previewLeaked }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard readyCount() > before, editor.string == "你好" else { throw Failure.offlinePreview }
        try await HostSnapshot.clickCandidate(host: window)
        try await Task.sleep(nanoseconds: 500_000_000)
        guard ((try? String(contentsOfFile: path)) ?? "").contains("annotation shown"), editor.string == "你好" else { throw Failure.offlinePreview }
        try await HostSnapshot.capture("english-explanation", host: window)
        try await send("\r", window: window)
        guard delegate.submissions.count == 3, delegate.submissions.last == "你好" else { throw Failure.returnWasNotForwarded }
        print("Learning mode passed: clicked native candidate showed Chinese annotation; Return submitted only the original Chinese.")
        settings.englishOutput = true
        try await Task.sleep(nanoseconds: 500_000_000)
        for character in "nihao " { try await send(String(character), window: window) }
        let second = readyCount()
        try await send("t", window: window, modifiers: [.maskControl, .maskAlternate])
        let secondDeadline = ProcessInfo.processInfo.systemUptime + 240
        while readyCount() == second, ProcessInfo.processInfo.systemUptime < secondDeadline {
            guard editor.string == "你好" else { throw Failure.previewLeaked }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        guard readyCount() > second, editor.string == "你好" else { throw Failure.offlinePreview }
        try await HostSnapshot.capture("english-candidate", host: window)
        try await send("\t", window: window)
        let english = editor.string
        guard SentencePolicy.language(of: english) == .english else { throw Failure.offlinePreview }
        try await send("\r", window: window)
        guard delegate.submissions.count == 4, delegate.submissions.last == english else { throw Failure.returnWasNotForwarded }
        print("Real offline IMK flow passed: Chinese source stayed unchanged while generating; Tab adopted English; Return submitted once.")
    }

    @MainActor private static func liveWebInput() async throws {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 650, height: 300))
        let window = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = web
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        web.loadHTMLString("""
        <html><body><form><input id='search' type='search'></form><textarea id='chat'></textarea><script>
        window.sent=[];
        document.querySelector('form').onsubmit=function(event){event.preventDefault();sent.push(['search',search.value]);search.value='';};
        chat.onkeydown=function(event){if(event.key==='Enter'&&!event.isComposing&&!event.shiftKey){event.preventDefault();sent.push(['chat',chat.value]);chat.value='';}};
        </script></body></html>
        """, baseURL: nil)
        for _ in 0..<80 {
            if (try? await web.evaluateJavaScript("document.getElementById('chat') !== null")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await selectMode(".Chinese")
        for field in ["search", "chat"] {
            _ = try await web.evaluateJavaScript("document.getElementById('\(field)').focus()")
            try await Task.sleep(nanoseconds: 500_000_000)
            for character in "nihao " { try await send(String(character), window: window) }
            let value = try await web.evaluateJavaScript("document.getElementById('\(field)').value") as? String
            guard value == "你好" else { throw Failure.liveWebInput }
            try await send("\r", window: window)
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let sent = try await web.evaluateJavaScript("window.sent") as? [[String]]
        guard sent == [["search", "你好"], ["chat", "你好"]] else { throw Failure.returnWasNotForwarded }
        print("Real IMK keycodes in WebKit search/chat controls passed; Return submitted each field exactly once.")
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
    @MainActor private static func send(_ text: String, window: NSWindow, modifiers: CGEventFlags = []) async throws {
        let codes: [String: UInt16] = ["a":0, "s":1, "d":2, "f":3, "h":4, "g":5, "z":6, "x":7, "c":8, "v":9,
            "b":11, "q":12, "w":13, "e":14, "r":15, "y":16, "t":17, "o":31, "u":32, "i":34, "p":35,
            "l":37, "j":38, "k":40, "n":45, "m":46, ".":47, " ":49, "\r":36, "\t":48, "\u{8}":51]
        let uppercase = text != text.lowercased()
        let code = codes[text.lowercased()] ?? 0
        for down in [true, false] {
            let hardware = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            hardware.flags = modifiers.union(uppercase ? .maskShift : [])
            // Unicode text injection bypasses IMEs. Exercise physical keycodes.
            hardware.postToPid(getpid())
        }
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
    enum Failure: Error { case previewLeaked, noTextClient, registration, liveChinese, liveEnglish, returnWasNotForwarded, systemControl, wrongInstalledBundle, offlinePreview, liveWebInput, hostSelectionChanged, liveBaidu }
}
