import SwiftUI
import AsideCore

@MainActor final class Preferences: ObservableObject {
    @Published var style: ExpressionStyle { didSet { UserDefaults.standard.set(style.rawValue, forKey: "style") } }
    @Published var model: String { didSet { UserDefaults.standard.set(model, forKey: "model") } }
    @Published var backend: String { didSet { UserDefaults.standard.set(backend, forKey: "backend") } }
    @Published var cloudModel: String { didSet { UserDefaults.standard.set(cloudModel, forKey: "cloudModel") } }
    @Published var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: "baseURL")
            cloudConsent = false
        }
    }
    @Published var cloudConsent = false
    @Published var automatic: Bool = false
    @Published var paused: Bool = false
    @Published var outputMode: Bool { didSet { UserDefaults.standard.set(outputMode, forKey: "outputMode") } }
    @Published var showExplanation: Bool { didSet { UserDefaults.standard.set(showExplanation, forKey: "showExplanation") } }
    @Published var autoDraft: Bool { didSet { UserDefaults.standard.set(autoDraft, forKey: "autoDraft") } }

    init() {
        style = ExpressionStyle(rawValue: UserDefaults.standard.string(forKey: "style") ?? "") ?? .casual
        model = UserDefaults.standard.string(forKey: "model") ?? ""
        backend = UserDefaults.standard.string(forKey: "backend") == "cloud" ? "cloud" : "local"
        cloudModel = UserDefaults.standard.string(forKey: "cloudModel") ?? ""
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "https://api.openai.com/v1"
        outputMode = UserDefaults.standard.bool(forKey: "outputMode")
        showExplanation = UserDefaults.standard.bool(forKey: "showExplanation")
        autoDraft = UserDefaults.standard.object(forKey: "autoDraft") as? Bool ?? true
    }

    var needsSetup: Bool { backend == "cloud" ? cloudModel.isEmpty : model.isEmpty }
}
