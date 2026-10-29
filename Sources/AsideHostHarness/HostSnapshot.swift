import AppKit
import ScreenCaptureKit
import AsideCore

/// CI-only: capture the fixture and visible IME windows, excluding other apps.
@MainActor enum HostSnapshot {
    static func capture(_ name: String, host: NSWindow) async throws {
        guard let output = ProcessInfo.processInfo.environment["ASIDE_SMOKE_OUTPUT"] else { return }
        try await Task.sleep(nanoseconds: 300_000_000)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return }
        let windows = content.windows.filter { window in
            let owner = window.owningApplication?.bundleIdentifier?.lowercased() ?? ""
            return window.windowID == CGWindowID(host.windowNumber)
                || owner == InputSourcePreferences.bundleID.lowercased()
                || owner.contains("inputmethodkit")
        }
        guard !windows.isEmpty else { return }
        var rectangle = windows[0].frame
        for window in windows.dropFirst() { rectangle = rectangle.union(window.frame) }
        rectangle = rectangle.insetBy(dx: -16, dy: -16).intersection(display.frame)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(x: rectangle.minX - display.frame.minX, y: rectangle.minY - display.frame.minY,
                                          width: rectangle.width, height: rectangle.height)
        configuration.width = Int(rectangle.width)
        configuration.height = Int(rectangle.height)
        configuration.showsCursor = false
        let bitmap = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: windows), configuration: configuration)
        guard let png = NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"), options: .atomic)
        print("Captured native fixture and IME windows:", name, "window count:", windows.count)
    }
}
