import XCTest
@testable import AsideCore

final class OfflineTests: XCTestCase {
    func testRuntimeEndpointAlwaysStaysOnLoopback() throws {
        let url = try OfflineEndpoint.completion(port: 28461)
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.path, "/v1/chat/completions")
        XCTAssertNil(url.query)
    }
    func testInvalidRuntimePortsRejected() {
        for port in [-1, 0, 443, 65536] { XCTAssertThrowsError(try OfflineEndpoint.completion(port: port)) }
    }
    func testOfflineResultValidated() throws {
        XCTAssertEqual(try WritingResult.parseJSON(#"{"expression":"Hello.","explanation":"日常问候。"}"#).expression, "Hello.")
        XCTAssertThrowsError(try WritingResult.parseJSON("{}"))
    }
}
