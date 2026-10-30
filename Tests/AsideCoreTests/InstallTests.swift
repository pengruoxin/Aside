import XCTest
@testable import AsideCore

final class InstallTests: XCTestCase {
    private let identifier = "io.github.pengruoxin.inputmethod.Aside"
    private func bundle(_ parent: URL, name: String, value: String, id: String? = nil) throws -> URL {
        let app = parent.appendingPathComponent(name + ".app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id ?? identifier, "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data(value.utf8).write(to: app.appendingPathComponent("marker"))
        return app
    }
    func testFailedCopyDoesNotMoveOldBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try bundle(root, name: "New", value: "new")
        let destination = try bundle(root, name: "Aside", value: "old")
        XCTAssertThrowsError(try InstallTransaction.install(source: source, destination: destination, backupRoot: root.appendingPathComponent("Backups"), identifier: identifier, validate: { _ in }, copy: { _, _ in throw TestFailure.copy }))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker")), "old")
    }
    func testUpgradeKeepsBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try bundle(root, name: "New", value: "new")
        let destination = try bundle(root, name: "Aside", value: "old")
        let backup = try InstallTransaction.install(source: source, destination: destination, backupRoot: root.appendingPathComponent("Backups"), identifier: identifier, validate: { _ in })
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker")), "new")
        XCTAssertEqual(try String(contentsOf: backup!.appendingPathComponent("marker")), "old")
    }
    func testFailedSwapRestoresOldBundle() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try bundle(root, name: "New", value: "new")
        let destination = try bundle(root, name: "Aside", value: "old")
        var moves = 0
        XCTAssertThrowsError(try InstallTransaction.install(source: source, destination: destination, backupRoot: root.appendingPathComponent("Backups"), identifier: identifier, validate: { _ in }, move: { from, to in
            moves += 1
            if moves == 2 { throw TestFailure.swap }
            try FileManager.default.moveItem(at: from, to: to)
        }))
        XCTAssertEqual(try String(contentsOf: destination.appendingPathComponent("marker")), "old")
    }
    enum TestFailure: Error { case copy, swap }
}
