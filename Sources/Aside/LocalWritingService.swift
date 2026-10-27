import Foundation
import AsideCore

/// Localhost only in this milestone. No secret, account, or remote data transfer.
struct LocalWritingService {
    private struct Payload: Encodable {
        let model: String
        let system: String
        let prompt: String
        let stream = false
        let format = "json"
    }
    private struct Envelope: Decodable { let response: String }

    func generate(_ writing: WritingRequest, model: String) async throws -> WritingResult {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WritingError.modelMissing }
        guard !writing.source.isEmpty, writing.source.count <= SentencePolicy.limit,
              SentencePolicy.language(of: writing.source) != .undetermined else { throw WritingError.invalidSource }
        var request = URLRequest(url: URL(string: "http://localhost:11434/api/generate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Payload(model: model, system: writing.systemPrompt, prompt: writing.source))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { if Task.isCancelled { throw CancellationError() }; throw WritingError.serviceUnavailable }
        guard let http = response as? HTTPURLResponse else { throw WritingError.serviceUnavailable }
        guard (200..<300).contains(http.statusCode) else { throw WritingError.serverFailure(http.statusCode) }
        guard data.count <= 256_000,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let json = envelope.response.data(using: .utf8),
              let result = try? JSONDecoder().decode(WritingResult.self, from: json) else { throw WritingError.invalidResult }
        return try WritingResult.validated(expression: result.expression, explanation: result.explanation)
    }
}
