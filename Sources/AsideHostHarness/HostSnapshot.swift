import AppKit
import ScreenCaptureKit
import AsideCore

/// CI-only: capture the fixture and visible IME windows, excluding other apps.
@MainActor enum HostSnapshot {
    static func clickCandidate(host: NSWindow) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let candidate = content.windows.first(where: { window in
            let owner = window.owningApplication?.bundleIdentifier.lowercased() ?? ""
            return window.windowID != CGWindowID(host.windowNumber) && window.frame.height < 180
                && window.frame.height > 18 && window.frame.width > 50
                && (owner == InputSourcePreferences.bundleID.lowercased() || owner.contains("inputmethodkit"))
        }), let owner = candidate.owningApplication else {
            throw NSError(domain: "Aside.CandidateFixture", code: 1)
        }
        let point = CGPoint(x: candidate.frame.midX, y: candidate.frame.midY)
        print("Clicking native candidate window:", candidate.windowID, owner.bundleIdentifier, candidate.frame)
        if let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, candidate.windowID) as? [[String: Any]] {
            print("Candidate Quartz bounds:", info.first?[kCGWindowBounds as String] as Any)
        }
        let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)!
        move.flags = []
        move.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: 150_000_000)
        print("Pointer after candidate move:", CGEvent(source: nil)?.location as Any)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)!
            print("Candidate mouse inherited flags:", event.flags.rawValue)
            event.flags = []
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            // Mouse events need WindowServer hit testing; the nonactivating
            // candidate panel has no key window for PID-only event delivery.
            event.post(tap: .cghidEventTap)
            try await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    static func capture(_ name: String, host: NSWindow) async throws {
        guard let output = ProcessInfo.processInfo.environment["ASIDE_SMOKE_OUTPUT"] else { return }
        try await Task.sleep(nanoseconds: 300_000_000)
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { return }
        let windows = content.windows.filter { window in
            let owner = window.owningApplication?.bundleIdentifier.lowercased() ?? ""
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
        configuration.showsCursor = name == "learning-click-result"
        let bitmap = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: windows), configuration: configuration)
        guard let png = NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]) else { return }
        try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"), options: Data.WritingOptions.atomic)
        print("Captured native fixture and IME windows:", name, "window count:", windows.count)
    }
}
