import Foundation

public enum InstallTransaction {
    /// Fully stage and validate before touching an existing input method.
    @discardableResult public static func install(
        source: URL, destination: URL, backupRoot: URL, identifier: String,
        validate: (URL) throws -> Void,
        copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
        move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) throws -> URL? {
        let files = FileManager.default
        guard source.standardizedFileURL != destination.standardizedFileURL,
              Bundle(url: source)?.bundleIdentifier == identifier else { throw InstallFailure.invalidBundle }
        let parent = destination.deletingLastPathComponent()
        try files.createDirectory(at: parent, withIntermediateDirectories: true)
        let staging = parent.appendingPathComponent(".Aside-install-" + UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        let prepared = staging.appendingPathComponent("Aside.app")
        try copy(source, prepared)
        guard Bundle(url: prepared)?.bundleIdentifier == identifier else { throw InstallFailure.invalidBundle }
        try validate(prepared)
        var backup: URL?
        if files.fileExists(atPath: destination.path) {
            guard Bundle(url: destination)?.bundleIdentifier == identifier else { throw InstallFailure.otherApplication }
            let backupFolder = backupRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try files.createDirectory(at: backupFolder, withIntermediateDirectories: true)
            let backupURL = backupFolder.appendingPathComponent("Aside.app")
            try move(destination, backupURL)
            backup = backupURL
        }
        do { try move(prepared, destination) }
        catch {
            if let backup {
                do { try move(backup, destination) }
                catch { throw InstallFailure.rollbackFailed(backup.path) }
            }
            throw error
        }
        return backup
    }
}

public enum InstallFailure: LocalizedError {
    case invalidBundle, otherApplication, rollbackFailed(String)
    public var errorDescription: String? {
        switch self {
        case .invalidBundle: return "输入法包不完整或标识不匹配，原有输入法未被覆盖。"
        case .otherApplication: return "目标位置存在其他应用，未覆盖。"
        case .rollbackFailed(let path): return "恢复旧输入法失败，备份仍保存在：\(path)。请手动检查后重试。"
        }
    }
}
