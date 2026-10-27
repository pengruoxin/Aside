import Foundation

public struct ServiceConfiguration {
    public let backend: String
    public let model: String
    public let baseURL: String
    public let key: String
    public let consent: Bool
    public init(backend: String, model: String, baseURL: String, key: String, consent: Bool) {
        self.backend = backend; self.model = model; self.baseURL = baseURL; self.key = key; self.consent = consent
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward source text or API keys to a redirected host.
    }
}

public struct WritingService {
    private let sessionConfiguration: URLSessionConfiguration
    public init(sessionConfiguration: URLSessionConfiguration = .ephemeral) { self.sessionConfiguration = sessionConfiguration }
    private struct Message: Encodable { let role: String; let content: String }
    private struct ChatPayload: Encodable {
        let model: String
        let messages: [Message]
        let stream = false
        let response_format = ["type": "json_object"]
    }
    private struct LocalPayload: Encodable {
        let model: String; let system: String; let prompt: String
        let stream = false
        let format = "json"
    }
    private struct LocalEnvelope: Decodable { let response: String }
    private struct ChatEnvelope: Decodable {
        struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
        let choices: [Choice]
    }

    public func generate(_ writing: WritingRequest, configuration: ServiceConfiguration) async throws -> WritingResult {
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WritingError.modelMissing }
        guard !writing.source.isEmpty, writing.source.count <= SentencePolicy.limit,
              SentencePolicy.language(of: writing.source) != .undetermined else { throw WritingError.invalidSource }
        var request: URLRequest
        if configuration.backend == "cloud" {
            guard configuration.consent else { throw ConfigurationError.cloudConsentRequired }
            guard !configuration.key.isEmpty else { throw ConfigurationError.missingKey }
            request = URLRequest(url: try CloudEndpoint.url(base: configuration.baseURL))
            request.setValue("Bearer \(configuration.key)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(ChatPayload(model: configuration.model, messages: [
                Message(role: "system", content: writing.systemPrompt), Message(role: "user", content: writing.source)
            ]))
        } else {
            request = URLRequest(url: URL(string: "http://localhost:11434/api/generate")!)
            request.httpBody = try JSONEncoder().encode(LocalPayload(model: configuration.model, system: writing.systemPrompt, prompt: writing.source))
        }
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let settings = sessionConfiguration.copy() as! URLSessionConfiguration
        settings.urlCache = nil
        settings.httpCookieStorage = nil
        let session = URLSession(configuration: settings, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WritingError.serviceUnavailable }
        guard (200..<300).contains(http.statusCode) else { throw ServiceHTTPError(status: http.statusCode) }
        guard data.count <= 256_000 else { throw WritingError.invalidResult }
        let text: String
        if configuration.backend == "cloud" {
            guard let envelope = try? JSONDecoder().decode(ChatEnvelope.self, from: data),
                  let content = envelope.choices.first?.message.content else { throw WritingError.invalidResult }
            text = content
        } else {
            guard let envelope = try? JSONDecoder().decode(LocalEnvelope.self, from: data) else { throw WritingError.invalidResult }
            text = envelope.response
        }
        return try WritingResult.parseJSON(text)
    }

    public func localModels() async throws -> [String] {
        var request = URLRequest(url: URL(string: "http://localhost:11434/api/tags")!)
        request.timeoutInterval = 5
        let session = URLSession(configuration: sessionConfiguration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count <= 1_000_000 else {
            throw WritingError.serviceUnavailable
        }
        struct Models: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }
        return try JSONDecoder().decode(Models.self, from: data).models.map(\.name)
    }
}

struct ServiceHTTPError: LocalizedError {
    let status: Int
    var errorDescription: String? {
        switch status {
        case 401, 403: return "服务拒绝访问，请检查 API Key 和模型使用权限。"
        case 404: return "未找到服务或模型，请检查 API 地址和模型名。"
        case 429: return "服务额度不足或请求太频繁，请稍后重试并检查账户额度。"
        default: return "翻译服务返回错误（\(status)），请检查配置或稍后重试。"
        }
    }
}
