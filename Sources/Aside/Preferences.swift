import SwiftUI
import AsideCore

@MainActor final class Preferences: ObservableObject {
    @Published var style: ExpressionStyle { didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") } }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "model") } }
    @Published var automatic: Bool = false
    @Published var paused: Bool = false
    @Published var outputMode: Bool = false
    @Published var showExplanation: Bool = false

    init() {
        style = ExpressionStyle(rawValue: UserDefaults.standard.string(forKey: "style") ?? "") ?? .casual
        model = UserDefaults.standard.string(forKey: "model") ?? ""
    }
}
