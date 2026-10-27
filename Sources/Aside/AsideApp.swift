import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
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
    }
}
