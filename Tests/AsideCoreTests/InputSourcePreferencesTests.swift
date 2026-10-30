import XCTest
@testable import AsideCore

final class InputSourcePreferencesTests: XCTestCase {
    func testRegistrationPreservesAppleSourcesAndAddsParentAndBothModes() {
        let apple: [String: Any] = ["InputSourceKind": "Keyboard Layout", "KeyboardLayout ID": 0, "KeyboardLayout Name": "U.S."]
        let result = InputSourcePreferences.enablingAside(in: [apple])
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0] as NSDictionary, apple as NSDictionary)
        XCTAssertEqual(result[1]["InputSourceKind"] as? String, "Keyboard Input Method")
        XCTAssertEqual(result[2]["Input Mode"] as? String, InputSourcePreferences.modes[0])
        XCTAssertEqual(result[3]["Input Mode"] as? String, InputSourcePreferences.modes[1])
        XCTAssertEqual(InputSourcePreferences.enablingAside(in: result) as NSArray, result as NSArray)
    }

    func testPartialRegistrationIsCompletedWithoutDuplicateMode() {
        let mode: [String: Any] = ["Bundle ID": InputSourcePreferences.bundleID, "InputSourceKind": "Input Mode", "Input Mode": InputSourcePreferences.modes[0]]
        let result = InputSourcePreferences.enablingAside(in: [mode])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.filter { ($0["Input Mode"] as? String) == InputSourcePreferences.modes[0] }.count, 1)
        XCTAssertTrue(result.contains { ($0["InputSourceKind"] as? String) == "Keyboard Input Method" })
    }
}
