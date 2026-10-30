import XCTest
@testable import AsideCore

final class InlineLayoutTests: XCTestCase {
    private let field = CGRect(x: 100, y: 200, width: 500, height: 44)
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    func testGrayTextUsesOnlyEmptySpaceAfterCaret() throws {
        let rect = try XCTUnwrap(InlineLayout.frame(field: field, caret: CGRect(x: 180, y: 212, width: 1, height: 20), visible: visible))
        XCTAssertEqual(rect.minX, 187)
        XCTAssertEqual(rect.maxX, 576) // trailing 24pt excludes search/clear controls
        XCTAssertEqual(rect.height, 20)
        XCTAssertTrue(field.contains(rect))
    }
    func testHidesWhenLessThan80PointsRemain() {
        XCTAssertNil(InlineLayout.frame(field: field, caret: CGRect(x: 510, y: 212, width: 1, height: 20), visible: visible))
    }
    func testDoesNotMoveToAnotherLineOrOutsideField() {
        XCTAssertNil(InlineLayout.frame(field: field, caret: CGRect(x: 180, y: 245, width: 1, height: 20), visible: visible))
        XCTAssertNil(InlineLayout.frame(field: field, caret: CGRect(x: 80, y: 212, width: 1, height: 20), visible: visible))
        XCTAssertNil(InlineLayout.frame(field: field, caret: CGRect(x: 180, y: 212, width: 1, height: 20), visible: CGRect(x: 0, y: 0, width: 1000, height: 210)))
    }
    func testSecondaryScreenMayUseNegativeCoordinates() throws {
        let rect = try XCTUnwrap(InlineLayout.frame(field: CGRect(x: -900, y: 80, width: 600, height: 100), caret: CGRect(x: -800, y: 130, width: 0, height: 22), visible: CGRect(x: -1000, y: 0, width: 1000, height: 800)))
        XCTAssertEqual(rect.minX, -794)
        XCTAssertEqual(rect.maxY, 152)
    }
    func testRejectsInvalidGeometry() {
        XCTAssertNil(InlineLayout.frame(field: .zero, caret: .zero, visible: visible))
        XCTAssertNil(InlineLayout.frame(field: field, caret: CGRect(x: .nan, y: 212, width: 1, height: 20), visible: visible))
        XCTAssertNil(InlineLayout.frame(field: field, caret: CGRect(x: 180, y: 212, width: 1, height: 200), visible: visible))
    }
}
