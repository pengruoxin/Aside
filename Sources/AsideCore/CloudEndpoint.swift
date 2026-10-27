import Foundation

public enum CloudEndpoint {
    public static func url(base: String) throws -> URL {
        let base = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: base),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw ConfigurationError.invalidEndpoint
        }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + (components.path.isEmpty ? "" : components.path + "/") + "chat/completions"
        guard let url = components.url else { throw ConfigurationError.invalidEndpoint }
        return url
    }
}

public enum ConfigurationError: LocalizedError {
    case invalidEndpoint, missingKey, cloudConsentRequired
    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "服务地址必须为 HTTPS API 基础地址，不可包含密钥、查询参数或片段。"
        case .missingKey: return "请在翻译服务设置中保存 API Key。"
        case .cloudConsentRequired: return "请先在设置中确认允许将当前句子发送到此云端服务。"
        }
    }
}

extension WritingResult {
    public static func parseJSON(_ text: String) throws -> WritingResult {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fence = String(repeating: "`", count: 3)
        if json.hasPrefix(fence), json.hasSuffix(fence), let newline = json.firstIndex(of: "\n") {
            json = String(json[json.index(after: newline)...].dropLast(3))
        }
        guard json.utf8.count <= 128_000, let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(WritingResult.self, from: data) else { throw WritingError.invalidResult }
        return try validated(expression: result.expression, explanation: result.explanation)
    }
}
