import Foundation

extension WritingResult {
    public static func parseJSON(_ text: String) throws -> WritingResult {
        var json = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let fence = String(repeating: "`", count: 3)
        if json.hasPrefix(fence), json.hasSuffix(fence), let line = json.firstIndex(of: "\n") {
            json = String(json[json.index(after: line)...].dropLast(3))
        }
        guard json.utf8.count <= 128_000, let data = json.data(using: .utf8),
              let output = try? JSONDecoder().decode(WritingResult.self, from: data) else { throw WritingError.invalidResult }
        return try validated(expression: output.expression, explanation: output.explanation)
    }
}
