import AppKit
import ScreenCaptureKit
import AsideOffline

/// Fixed CI screenshots of the shipped native views; never captures other apps.
@MainActor enum InstallerScreenshots {
    private static var started = false
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard !started, let flag = arguments.firstIndex(of: "--snapshot-ui"), arguments.count > flag + 1 else { return }
        started = true
        let folder = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        Task { @MainActor in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard let installer = NSApp.windows.first(where: { $0.title == "安装句外输入法" }) else { throw CaptureError.noWindow }
                try await capture(installer, to: folder.appendingPathComponent("installer.png"))
                SettingsWindow.shared.show()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard let settings = NSApp.windows.first(where: { $0.title == "句外输入法设置" }) else { throw CaptureError.noWindow }
                try await capture(settings, to: folder.appendingPathComponent("settings.png"))
                print("Native installer and settings views rendered successfully.")
                exit(0)
            } catch { fputs("Native UI capture failed: \(error)\n", stderr); exit(1) }
        }
    }

    private static func capture(_ window: NSWindow, to destination: URL) async throws {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(nanoseconds: 300_000_000)
        // WindowGroup uses layer-backed hosting; cacheDisplay can return an
        // empty bitmap even when the window is visible. Capture this app's
        // own composited window instead, including the actual native controls.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let visible = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else { throw CaptureError.noWindow }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * window.backingScaleFactor)
        configuration.height = Int(window.frame.height * window.backingScaleFactor)
        configuration.showsCursor = false
        let bitmap = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: visible), configuration: configuration)
        let image = NSBitmapImageRep(cgImage: bitmap)
        guard let png = image.representation(using: .png, properties: [:]), png.count > 5000 else { throw CaptureError.emptyView }
        try png.write(to: destination, options: .atomic)
    }

    private enum CaptureError: Error { case noWindow, emptyView }
}
