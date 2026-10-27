import XCTest
@testable import AsideCore

final class ProviderTests: XCTestCase {
    func testAutomaticReadLossDoesNotDiscardManualSelection() {
        XCTAssertFalse(WritingOrigin.selection.discardWhenAutomaticContextIsLost)
        XCTAssertTrue(WritingOrigin.automatic.discardWhenAutomaticContextIsLost)
        XCTAssertFalse(WritingOrigin.editor.isExternal)
        XCTAssertTrue(WritingOrigin.selection.isExternal)
    }
    func testCloudEndpointAppendsPathWithoutDuplicateSlash() throws {
        XCTAssertEqual(try CloudEndpoint.url(base: "https://api.example.com/v1/").absoluteString, "https://api.example.com/v1/chat/completions")
    }
    func testCloudEndpointRejectsCredentialsHTTPAndQuery() {
        for url in ["http://api.example.com/v1", "https://user:secret@example.com/v1", "https://example.com/v1?key=secret", "file:///tmp", "https://example.com/#fragment"] {
            XCTAssertThrowsError(try CloudEndpoint.url(base: url), url)
        }
    }
    func testParsesPlainAndFencedJSON() throws {
        let json = #"{"expression":"This may work.","explanation":"may 保留不确定性。"}"#
        XCTAssertEqual(try WritingResult.parseJSON(json).expression, "This may work.")
        let fence = String(repeating: "`", count: 3)
        XCTAssertEqual(try WritingResult.parseJSON(fence + "json\n" + json + "\n" + fence).expression, "This may work.")
    }
    func testRejectsIncompleteAndEmptyResults() {
        for json in ["{}", #"{"expression":"hello"}"#, #"{"expression":" ","explanation":" "}"#, "not JSON"] {
            XCTAssertThrowsError(try WritingResult.parseJSON(json))
        }
    }
}
