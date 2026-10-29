import AppKit
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
                try capture(installer, to: folder.appendingPathComponent("installer.png"))
                SettingsWindow.shared.show()
                try await Task.sleep(nanoseconds: 1_000_000_000)
                guard let settings = NSApp.windows.first(where: { $0.title == "句外输入法设置" }) else { throw CaptureError.noWindow }
                try capture(settings, to: folder.appendingPathComponent("settings.png"))
                print("Native installer and settings views rendered successfully.")
                exit(0)
            } catch { fputs("Native UI capture failed: \(error)\n", stderr); exit(1) }
        }
    }

    private static func capture(_ window: NSWindow, to destination: URL) throws {
        guard let view = window.contentView else { throw CaptureError.noWindow }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard view.bounds.width >= 500, view.bounds.height >= 300,
              let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CaptureError.emptyView }
        view.cacheDisplay(in: view.bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else { throw CaptureError.emptyView }
        try png.write(to: destination, options: .atomic)
    }

    private enum CaptureError: Error { case noWindow, emptyView }
}
