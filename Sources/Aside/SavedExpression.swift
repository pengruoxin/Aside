import Foundation
import AsideCore

struct SavedExpression: Identifiable, Codable {
    var id = UUID()
    let source: String
    let expression: String
    let explanation: String
    let style: ExpressionStyle
    var date = Date()

    static func load() -> [SavedExpression] {
        guard let data = UserDefaults.standard.data(forKey: "savedExpressions"),
              let entries = try? JSONDecoder().decode([SavedExpression].self, from: data) else { return [] }
        return Array(entries.prefix(500))
    }
    static func persist(_ entries: [SavedExpression]) {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: "savedExpressions") }
    }
}
