import AppKit
import SwiftUI
import AsideCore

/// Runs only with the explicit CI flag. No model connection, API key or AX permission.
@MainActor enum NativeSmoke {
    static func run() async throws {
        let path = ProcessInfo.processInfo.environment["ASIDE_SMOKE_DIR"] ?? FileManager.default.currentDirectoryPath + "/dist/ui"
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let assistant = AssistantModel.shared
        assistant.preferences.autoDraft = false
        assistant.preferences.style = .academic
        assistant.draft = "我觉得这个方法可能不太适合小样本研究。"
        assistant.resultSource = assistant.draft
        assistant.result = try WritingResult.validated(expression: "This approach may be less suitable for studies with small sample sizes.", explanation: "may be less suitable 保留了“可能不太适合”的审慎语气。")
        assistant.message = "界面预览 · 示例表达"
        NSApp.appearance = NSAppearance(named: .aqua)
        let editorWindow = makeWindow(WritingView(assistant: assistant, preferences: assistant.preferences), size: NSSize(width: 660, height: 540))
        try await Task.sleep(nanoseconds: 1_500_000_000)
        try capture(editorWindow, to: path + "/writing.png")
        guard let editor = findEditor(in: editorWindow.contentView!) else { throw SmokeError.noEditor }
        let old = editor.string
        let replacement = "This could work."
        let range = NSRange(location: 0, length: old.utf16.count)
        guard editor.shouldChangeText(in: range, replacementString: replacement) else { throw SmokeError.editFailed }
        editor.textStorage?.replaceCharacters(in: range, with: replacement)
        editor.didChangeText()
        guard editor.string == replacement else { throw SmokeError.editFailed }
        editor.undoManager?.undo()
        guard editor.string == old else { throw SmokeError.undoFailed }
        editorWindow.close()
        let settings = makeWindow(PreferencesView(preferences: assistant.preferences, assistant: assistant), size: NSSize(width: 640, height: 690))
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try capture(settings, to: path + "/settings.png")
        settings.close()
        let welcome = makeWindow(WelcomeView(assistant: assistant, preferences: assistant.preferences, finish: {}), size: NSSize(width: 620, height: 680))
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try capture(welcome, to: path + "/welcome.png")
        welcome.close()
        try Data("Native launch, NSTextView editing, undo and three UI captures passed.\n".utf8).write(to: URL(fileURLWithPath: path + "/smoke.txt"))
    }

    private static func makeWindow<V: View>(_ view: V, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return window
    }
    private static func capture(_ window: NSWindow, to path: String) throws {
        guard let view = window.contentView else { throw SmokeError.captureFailed }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw SmokeError.captureFailed }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SmokeError.captureFailed }
        try png.write(to: URL(fileURLWithPath: path))
    }
    private static func findEditor(in view: NSView) -> NSTextView? {
        if let editor = view as? NSTextView { return editor }
        return view.subviews.compactMap { findEditor(in: $0) }.first
    }
    enum SmokeError: Error { case noEditor, editFailed, undoFailed, captureFailed }
}
