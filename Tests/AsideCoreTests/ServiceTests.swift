import XCTest
@testable import AsideCore

private final class FixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let output = #"{"expression":"This may work.","explanation":"may 保留不确定性。"}"#
        let cloud = request.url?.host != "localhost"
        let authorized = !cloud || request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key"
        let status = authorized ? 200 : 401
        let body: [String: Any] = cloud ? ["choices": [["message": ["content": output]]]] : ["response": output]
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ServiceTests: XCTestCase {
    private func service() -> WritingService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return WritingService(sessionConfiguration: configuration)
    }
    func testOllamaResponseIsParsed() async throws {
        let result = try await service().generate(.init(source: "这可能可行。", style: .academic),
            configuration: .init(backend: "local", model: "fixture", baseURL: "", key: "", consent: false))
        XCTAssertEqual(result.expression, "This may work.")
    }
    func testCloudSendsAuthorizationAndParsesResponse() async throws {
        let result = try await service().generate(.init(source: "It might work.", style: .academic),
            configuration: .init(backend: "cloud", model: "fixture", baseURL: "https://fixture.invalid/v1", key: "test-key", consent: true))
        XCTAssertEqual(result.expression, "This may work.")
    }
    func testCloudDoesNotSendWithoutConsent() async {
        do {
            _ = try await service().generate(.init(source: "Hello.", style: .casual),
                configuration: .init(backend: "cloud", model: "fixture", baseURL: "https://fixture.invalid/v1", key: "test-key", consent: false))
            XCTFail("Cloud request must require consent")
        } catch {
            XCTAssertTrue(error is ConfigurationError)
        }
    }
    func testCloudReportsAuthenticationFailure() async {
        do {
            _ = try await service().generate(.init(source: "Hello.", style: .casual),
                configuration: .init(backend: "cloud", model: "fixture", baseURL: "https://fixture.invalid/v1", key: "wrong-key", consent: true))
            XCTFail("Wrong key must not succeed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("API Key"))
        }
    }
}
