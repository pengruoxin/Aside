import Foundation
import Carbon
import AsideCore

@MainActor public enum InputSourceRegistration {
    /// Some macOS versions report noErr while leaving the parent IME disabled.
    /// In that case, merge the same entries System Settings stores, preserving
    /// all existing sources. A new login may still be needed to refresh TIS.
    public static func enableInstalledBundle(_ bundle: URL) throws {
        guard TISRegisterInputSource(bundle as CFURL) == noErr else { throw RegistrationError.failed }
        let query = [kTISPropertyBundleID as String: InputSourcePreferences.bundleID] as CFDictionary
        let sources = TISCreateInputSourceList(query, true).takeRetainedValue() as! [TISInputSource]
        guard !sources.isEmpty else { throw RegistrationError.failed }
        for source in sources { _ = TISEnableInputSource(source) }
        let enabled = sources.allSatisfy { source in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
            return CFBooleanGetValue(unsafeBitCast(raw, to: CFBoolean.self))
        }
        if enabled { return }

        let domain = "com.apple.HIToolbox" as CFString
        let key = "AppleEnabledInputSources" as CFString
        let raw = CFPreferencesCopyAppValue(key, domain)
        guard raw == nil || raw is [[String: Any]] else { throw RegistrationError.unexpectedPreferences }
        let existing = raw as? [[String: Any]] ?? []
        let backup = OfflinePaths.support.appendingPathComponent("InputSources-before-Aside.plist")
        if !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: existing, format: .xml, options: 0)
            try data.write(to: backup, options: .atomic)
        }
        CFPreferencesSetAppValue(key, InputSourcePreferences.enablingAside(in: existing) as CFArray, domain)
        guard CFPreferencesAppSynchronize(domain) else { throw RegistrationError.failed }
    }

    public enum RegistrationError: LocalizedError {
        case failed, unexpectedPreferences
        public var errorDescription: String? {
            "输入法已复制，但系统输入源启用尚未完成。请退出登录后重新登录，在键盘设置添加句外。"
        }
    }
}
