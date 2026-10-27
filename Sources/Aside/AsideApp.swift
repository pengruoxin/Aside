import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var welcomeWindow: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        if CommandLine.arguments.contains("--ui-smoke-test") {
            Task { @MainActor in
                do {
                    try await NativeSmoke.run()
                    NSApp.terminate(nil)
                } catch {
                    fputs("Native smoke failed: \(error)\n", stderr)
                    exit(1)
                }
            }
        } else if !UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
            let assistant = AssistantModel.shared
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 680),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "欢迎使用句外 Aside"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WelcomeView(assistant: assistant, preferences: assistant.preferences, finish: { [weak self] in
                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
                self?.welcomeWindow?.close()
            }))
            welcomeWindow = window
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func processSelection(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: NSPasteboard.PasteboardType("NSStringPboardType")), !text.isEmpty else {
            error.pointee = "没有收到选中文字。"; return
        }
        AssistantModel.shared.processServiceText(text)
        // Keep the original application's focus. The result is available via the menu bar.
    }
}

@main @MainActor struct AsideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var assistant = AssistantModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(assistant: assistant, preferences: assistant.preferences)
        } label: {
            Text(assistant.busy ? "句外…" : (assistant.result == nil ? "句外" : "句外 ·"))
        }.menuBarExtraStyle(.window)
        Window("句外 Aside", id: "writing") {
            WritingView(assistant: assistant, preferences: assistant.preferences)
        }.defaultSize(width: 600, height: 430)
        Window("句外偏好设置", id: "preferences") {
            PreferencesView(preferences: assistant.preferences, assistant: assistant)
        }.defaultSize(width: 570, height: 680)
        Settings {
            PreferencesView(preferences: assistant.preferences, assistant: assistant)
        }
    }
}
