import XCTest

final class MetadataTests: XCTestCase {
    func testInputSourceIdentityUsesRequiredInputMethodNamespace() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/InputMethod-Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let id = try XCTUnwrap(info["CFBundleIdentifier"] as? String)
        XCTAssertTrue(id.contains(".inputmethod."), "InputMethodKit expects the literal lower-case inputmethod namespace.")
        XCTAssertEqual(info["TISInputSourceID"] as? String, id)
        XCTAssertEqual(info["InputMethodServerDelegateClass"] as? String, info["InputMethodServerControllerClass"] as? String)
        let component = try XCTUnwrap(info["ComponentInputModeDict"] as? [String: Any])
        let modes = try XCTUnwrap(component["tsInputModeListKey"] as? [String: [String: Any]])
        XCTAssertEqual(modes[id + ".Chinese"]?["TISIntendedLanguage"] as? String, "zh-Hans")
        XCTAssertEqual(modes[id + ".English"]?["TISIntendedLanguage"] as? String, "en")
    }
}
