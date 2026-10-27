import AppKit
import Combine
import AsideCore

@MainActor final class AssistantModel: ObservableObject {
    static let shared = AssistantModel()
    let preferences = Preferences()
    let accessibility = AccessibilityReader()
    @Published var draft = ""
    @Published var result: WritingResult?
    @Published var resultSource = ""
    @Published var busy = false
    @Published var message = "中文翻译，英文改写。保留苹果拼音与 ABC。"
    @Published var isExternal = false
    @Published var explanationExpanded = false
    @Published var saved = SavedExpression.load()
    var composing = false
    private var generation: Task<Void, Never>?
    private var polling: AnyCancellable?
    private var preferencesSubscription: AnyCancellable?
    private var activeApplicationObserver: NSObjectProtocol?
    private var version = UUID()
    private var stableKey = ""
    private var stableSince = Date()
    private var submittedKey = ""

    private init() {
        polling = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.poll() }
        preferencesSubscription = preferences.objectWillChange.sink { [weak self] _ in
            self?.invalidate()
            self?.stableKey = ""
            self?.submittedKey = ""
        }
        activeApplicationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
                self.stableKey = ""
                self.submittedKey = ""
                if self.isExternal { self.invalidate() }
            }
        }
    }

    func invalidate() {
        version = UUID()
        generation?.cancel()
        generation = nil
        result = nil
        resultSource = ""
        busy = false
    }

    func draftChanged() {
        invalidate()
        isExternal = false
        guard !preferences.paused, preferences.autoDraft, !composing, let source = SentencePolicy.completed(draft) else { return }
        generate(source: source, external: false, debounce: true)
    }

    func processDraft() {
        guard !composing else { message = "请先确认当前中文候选词。"; return }
        generate(source: draft, external: false)
    }

    /// macOS Services provides exactly the text explicitly selected by the user.
    func processServiceText(_ source: String) {
        generate(source: source, external: true)
    }

    func processSelection() {
        guard let snapshot = accessibility.capture(selectionOnly: true) else {
            message = "没有读到选中文字。可在原应用的“服务”菜单中选择“使用句外处理”，或粘贴到句外。"
            return
        }
        generate(source: snapshot.text, external: true)
    }

    private func generate(source: String, external: Bool, debounce: Bool = false) {
        invalidate()
        guard !preferences.paused else { message = "句外已暂停。"; return }
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source.count <= SentencePolicy.limit,
              SentencePolicy.language(of: source) != .undetermined else { message = WritingError.invalidSource.localizedDescription; return }
        isExternal = external
        let token = version
        let style = preferences.style
        let configuration = serviceConfiguration()
        busy = true
        message = external ? "正在处理选中的文字…" : "正在生成英文表达…"
        generation = Task { [weak self] in
            do {
                if debounce { try await Task.sleep(nanoseconds: 900_000_000) }
                try Task.checkCancellation()
                let output = try await WritingService().generate(WritingRequest(source: source, style: style), configuration: configuration)
                try Task.checkCancellation()
                guard let self, self.version == token else { return }
                self.result = output
                self.resultSource = source
                self.busy = false
                self.explanationExpanded = self.preferences.showExplanation
                self.message = SentencePolicy.language(of: source) == .chinese ? "中文 → 英文 · \(style.title)" : "英文改写 · \(style.title)"
            } catch {
                guard let self, self.version == token, !Task.isCancelled else { return }
                self.busy = false
                self.message = error.localizedDescription
            }
        }
    }

    func copyResult() {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result.expression, forType: .string)
        message = "已复制英文，请在原应用中自行粘贴。"
    }

    func serviceConfiguration() -> ServiceConfiguration {
        ServiceConfiguration(backend: preferences.backend,
                             model: preferences.backend == "cloud" ? preferences.cloudModel : preferences.model,
                             baseURL: preferences.baseURL,
                             key: preferences.backend == "cloud" ? (KeychainStore.load(endpoint: preferences.baseURL) ?? "") : "",
                             consent: preferences.cloudConsent)
    }

    func saveResult() {
        guard let result else { return }
        guard !saved.contains(where: { $0.source == resultSource && $0.expression == result.expression }) else { message = "这句已经收藏了。"; return }
        guard saved.count < 500 else { message = "已达到 500 条收藏，请先整理收藏。"; return }
        saved.insert(SavedExpression(source: resultSource, expression: result.expression, explanation: result.explanation, style: preferences.style), at: 0)
        SavedExpression.persist(saved)
        message = "已收藏，可在偏好设置的“收藏”中回看。"
    }

    func removeSaved(_ id: UUID) {
        saved.removeAll { $0.id == id }
        SavedExpression.persist(saved)
    }

    func clearContent() {
        draft = ""
        invalidate()
        message = "已清除当前文字与结果。"
    }

    func replaceDraft() {
        guard !isExternal, preferences.outputMode, let result,
              draft.trimmingCharacters(in: .whitespacesAndNewlines) == resultSource else { return }
        draft = result.expression
        invalidate()
        message = "已替换句外编辑区，没有发送。"
    }

    private func poll() {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
        guard preferences.automatic, !preferences.paused,
              let snapshot = accessibility.capture(selectionOnly: false),
              let source = SentencePolicy.completed(snapshot.text) else {
            stableKey = ""
            if isExternal && preferences.automatic { invalidate() }
            return
        }
        let key = "\(snapshot.processID):\(snapshot.identity):\(source)"
        if key != stableKey {
            if isExternal { invalidate() }
            stableKey = key
            stableSince = Date()
            return
        }
        guard Date().timeIntervalSince(stableSince) >= 1.5, key != submittedKey else { return }
        submittedKey = key
        generate(source: source, external: true)
    }
}
