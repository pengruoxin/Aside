import AppKit
import ApplicationServices

/// Read-only: intentionally no AXSetAttributeValue or simulated keyboard events.
@MainActor final class AccessibilityReader {
    struct Snapshot {
        let text: String
        let processID: pid_t
        let identity: CFHashCode
    }

    var trusted: Bool { AXIsProcessTrusted() }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    func capture(selectionOnly: Bool) -> Snapshot? {
        guard trusted, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        // Terminals, password managers and unknown controls do not participate in automatic reads.
        let excluded = ["com.apple.Terminal", "com.googlecode.iterm2", "com.apple.keychainaccess", "com.agilebits.onepassword7", "com.1password.1password"]
        guard !excluded.contains(app.bundleIdentifier ?? "") else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let raw = attribute(application, "AXFocusedUIElement"), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(raw, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.15)
        let role = attribute(element, "AXRole") as? String
        let subrole = attribute(element, "AXSubrole") as? String
        guard subrole != "AXSecureTextField", role == "AXTextField" || role == "AXTextArea" else { return nil }
        if selectionOnly {
            guard let selected = attribute(element, "AXSelectedText") as? String, !selected.isEmpty, selected.count <= 2000 else { return nil }
            return Snapshot(text: selected, processID: app.processIdentifier, identity: CFHash(element))
        }
        // Strict opt-in allowlist; do not assume an arbitrary app exposes composition state reliably.
        guard ["com.apple.Notes", "com.apple.TextEdit"].contains(app.bundleIdentifier ?? ""),
              let value = attribute(element, "AXValue") as? String, !value.isEmpty, value.utf16.count <= 8000,
              let rawRange = attribute(element, "AXSelectedTextRange"), CFGetTypeID(rawRange) == AXValueGetTypeID() else { return nil }
        let axRange = unsafeBitCast(rawRange, to: AXValue.self)
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetType(axRange) == .cfRange, AXValueGetValue(axRange, .cfRange, &range),
              range.length == 0, range.location == value.utf16.count else { return nil }
        return Snapshot(text: value, processID: app.processIdentifier, identity: CFHash(element))
    }
}
