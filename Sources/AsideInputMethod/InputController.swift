import AppKit
import InputMethodKit
import Carbon
import AsideCore
import AsideOffline

@objc(AsideInputController) final class InputController: IMKInputController {
    private var composition = SentenceComposition()
    private var rime: RimeEngine?
    private var target: IMKTextInput?
    private var active = false
    private var englishMode = false
    private var generation: Task<Void, Never>?
    private var modeID = ""
    private var hasMarkedText = false
    private var sourceStart: Int?
    private var markedStart: Int?
    private var sessionID = UUID()
    private var sourceSession: UUID?
    private weak var sourceClient: AnyObject?
    private var sourceBundleID: String?
    private var canInspectSource = false
    private var preferencesObserver: NSObjectProtocol?
    deinit {
        generation?.cancel()
        if let preferencesObserver { DistributedNotificationCenter.default().removeObserver(preferencesObserver) }
    }
    private lazy var panel: IMKCandidates? = {
        let panel = IMKCandidates(server: server(), panelType: kIMKSingleRowSteppingCandidatePanel)
        panel?.setAttributes([IMKCandidatesSendServerKeyEventFirst: NSNumber(value: true)])
        return panel
    }()

    override func recognizedEvents(_ sender: Any!) -> Int {
        imeDiagnostic("recognizedEvents queried")
        return Int(NSEvent.EventTypeMask.keyDown.union(.leftMouseDown).union(.rightMouseDown).rawValue)
    }

    override func activateServer(_ sender: Any!) {
        imeDiagnostic("activateServer called; text client: \(sender is IMKTextInput)")
        MainActor.assumeIsolated {
            if active { commitOriginal() }
            generation?.cancel()
            composition.reset()
            sourceStart = nil
            markedStart = nil
            sessionID = UUID()
            sourceSession = nil
            sourceClient = nil
            sourceBundleID = nil
            canInspectSource = false
            hasMarkedText = false
            target = sender as? IMKTextInput
            active = true
            if rime == nil { rime = RimeEngine() }
            rime?.clear()
            updateMode()
            imeDiagnostic(englishMode ? "activated English" : "activated Chinese")
            if preferencesObserver == nil {
                _ = OfflineConfiguration.shared
                preferencesObserver = DistributedNotificationCenter.default().addObserver(forName: OfflineConfiguration.notification, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.active else { return }
                        self.generation?.cancel()
                        self.composition.invalidate()
                        self.refresh()
                    }
                }
            }
        }
    }
    override func deactivateServer(_ sender: Any!) {
        MainActor.assumeIsolated {
            commitOriginal()
            active = false
            target = nil
            panel?.hide()
        }
    }
    override func commitComposition(_ sender: Any!) {
        MainActor.assumeIsolated { commitOriginal() }
    }

    @MainActor private func updateMode() {
        if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            modeID = unsafeBitCast(pointer, to: CFString.self) as String
        }
        englishMode = modeID.hasSuffix(".English")
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        MainActor.assumeIsolated { process(event, sender: sender) }
    }
    @MainActor private func process(_ event: NSEvent?, sender: Any?) -> Bool {
        imeDiagnostic("handle event; active: \(active); text client: \(sender is IMKTextInput)")
        guard let event, active, let client = sender as? IMKTextInput else { return false }
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            commitOriginal()
            return false
        }
        if let target, (target as AnyObject) !== (client as AnyObject) {
            commitOriginal()
            composition.reset()
        }
        target = client
        if rime?.context.preedit.isEmpty ?? true,
           !composition.source.isEmpty, canInspectSource, ownedRange() == nil {
            forgetSentence()
        }
        let oldMode = englishMode
        updateMode()
        if oldMode != englishMode { commitOriginal() }
        let key = event.charactersIgnoringModifiers ?? ""
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.intersection([.command, .control, .option, .shift]) == [.control, .option], key.lowercased() == "t" {
            confirmPinyin()
            refresh()
            requestTranslation(manual: true)
            return true
        }
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            commitOriginal()
            return false
        }
        let context = rime?.context ?? RimeEngine.Context()
        let composingPinyin = !englishMode && !context.preedit.isEmpty
        if composingPinyin && [123, 124, 125, 126].contains(event.keyCode) {
            // Native candidate UI owns navigation and reports its highlighted string below.
            return false
        }
        if event.keyCode == 53 { // Escape: dismiss learning first; never throw away selected words.
            if !composingPinyin && composition.source.isEmpty { return false }
            generation?.cancel()
            if composingPinyin { rime?.clear(); composition.invalidate(); refresh() }
            else if composition.preview != nil { composition.invalidate(); refresh() }
            else { commitOriginal() }
            return true
        }
        if event.keyCode == 48, !flags.contains(.shift), !composingPinyin, composition.preview != nil,
           OfflineConfiguration.shared.englishOutput {
            if ownedRange() != nil { adoptEnglish(); return true }
            forgetSentence()
            OfflineConfiguration.shared.status = "当前输入框仅支持学习提示，已保留原文并将 Tab 交还应用。"
            return false
        }
        if event.keyCode == 48, composingPinyin {
            if let rime, rime.process(0xff09) { consumeCommit() }
            else { confirmPinyin() }
            refresh()
            return true
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if composingPinyin {
                // First Return confirms composition, not sending a message.
                // Rime ExpressEditor binds Return to raw Latin input. Commit
                // the current Chinese conversion explicitly for Mac behavior.
                confirmPinyin()
                refresh()
                return true
            }
            commitOriginal()
            return false // Host gets the real Return once, preserving its search/send setting.
        }
        if [48, 115, 119, 123, 124, 125, 126].contains(event.keyCode), !composingPinyin {
            commitOriginal()
            return false
        }
        generation?.cancel()
        if event.keyCode == 51 {
            if composingPinyin {
                _ = rime?.process(0xff08)
                composition.invalidate()
                refresh()
                return true
            }
            guard !composition.source.isEmpty else { return false }
            // The host owns confirmed text, including its native deletion/undo.
            // Predict only a verified single grapheme deletion. The next event
            // rechecks host text/caret, so unusual host behavior resets safely.
            if ownedRange() != nil {
                composition.backspace()
                panel?.hide()
                if composition.source.isEmpty { forgetSentence() }
            } else { forgetSentence() }
            return false
        }
        guard let chars = event.characters, !chars.isEmpty else { return false }
        let functionKey = chars.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) }
        if functionKey && !composingPinyin {
            commitOriginal()
            return false
        }
        if composition.preview != nil {
            // A completed sentence starts fresh. A manual mid-sentence preview
            // is invalidated while its confirmed words remain in context.
            if composition.completeSentence != nil { commitOriginal() }
            else { composition.invalidate() }
        }
        if !englishMode, let rime, rime.available {
            let special: [UInt16: Int32] = [123: 0xff51, 124: 0xff53, 125: 0xff54, 126: 0xff52, 116: 0xff55, 121: 0xff56, 117: 0xffff]
            let value = special[event.keyCode] ?? chars.unicodeScalars.first.map { Int32($0.value) } ?? 0
            let handled = rime.process(value, modifiers: flags.contains(.shift) ? 1 : 0)
            consumeCommit() // Rime may commit before declining punctuation.
            if handled {
                composition.invalidate()
                refresh()
                requestTranslation(manual: false)
                return true
            }
            confirmPinyin()
        }
        if functionKey || chars.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) && $0.value != 32 }) {
            commitOriginal()
            return false
        }
        let punctuation = [",": "，", ".": "。", "?": "？", "!": "！", ":": "：", ";": "；"]
        let text = englishMode ? chars : (punctuation[chars] ?? chars)
        appendConfirmed(text)
        if composition.source.count > 600 {
            commitOriginal()
            OfflineConfiguration.shared.status = "本段较长，已正常提交原文；请按句处理。"
            return true
        }
        refresh()
        requestTranslation(manual: false)
        return true
    }

    @MainActor private func consumeCommit() {
        if let text = rime?.takeCommit(), !text.isEmpty { appendConfirmed(text) }
    }
    @MainActor private func appendConfirmed(_ text: String) {
        guard let target else { return }
        let startsSentence = composition.source.isEmpty
        if startsSentence {
            let start = markedStart ?? target.selectedRange().location
            sourceStart = start == NSNotFound ? nil : start
            sourceSession = sessionID
            sourceClient = target as AnyObject
            sourceBundleID = target.bundleIdentifier()
        }
        target.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        hasMarkedText = false
        markedStart = nil
        composition.append(text)
        // Some clients expose typing but no document readback. They can still
        // learn from this session's typed text; replacement stays fail-closed.
        if startsSentence { canInspectSource = ownedRange() != nil }
        if composition.source.count > 600 {
            forgetSentence()
            OfflineConfiguration.shared.status = "本段较长，已保留原文；请从新句子继续学习。"
        }
    }
    @MainActor private func forgetSentence() {
        generation?.cancel()
        composition.reset()
        sourceStart = nil
        sourceSession = nil
        sourceClient = nil
        sourceBundleID = nil
        canInspectSource = false
        panel?.hide()
    }
    @MainActor private func ownedRange() -> NSRange? {
        guard active, let target, let start = sourceStart else { imeDiagnostic("range: no active anchor"); return nil }
        // uniqueClientIdentifierString() wraps globallyUniqueString: it creates
        // a new token per call, not a persistent field identity (IMKInputSession.h).
        guard sourceSession == sessionID, sourceClient === (target as AnyObject),
              let sourceBundleID, !sourceBundleID.isEmpty,
              target.bundleIdentifier() == sourceBundleID else { imeDiagnostic("range: client or session changed"); return nil }
        guard let range = CommittedTextRange.candidate(start: start,
                utf16Length: composition.source.utf16.count,
                selection: target.selectedRange(), marked: target.markedRange()) else { imeDiagnostic("range: selection or mark changed"); return nil }
        guard let substring = target.attributedSubstring(from: range) else { imeDiagnostic("range: host substring unavailable"); return nil }
        guard substring.string == composition.source, substring.length == range.length else { imeDiagnostic("range: host text changed"); return nil }
        return range
    }
    @MainActor private func confirmPinyin() {
        if !(rime?.context.preedit.isEmpty ?? true) {
            rime?.commit()
            consumeCommit()
            rime?.clear()
        }
    }
    @MainActor private func commitOriginal() {
        generation?.cancel()
        confirmPinyin()
        if hasMarkedText {
            target?.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        hasMarkedText = false
        markedStart = nil
        forgetSentence()
    }
    @MainActor private func adoptEnglish() {
        generation?.cancel()
        guard let range = ownedRange(), let text = composition.englishReplacement else {
            forgetSentence()
            OfflineConfiguration.shared.status = "输入位置已变化，已保留原文。请在当前句子重新生成。"
            return
        }
        rime?.clear()
        panel?.hide()
        target?.insertText(text, replacementRange: range)
        hasMarkedText = false
        forgetSentence()
    }
    @MainActor private func refresh() {
        guard active, let target else { return }
        let context = rime?.context ?? RimeEngine.Context()
        let preedit = englishMode ? "" : context.preedit
        let text = composition.hostMarkedText(preedit: preedit)
        // An empty refresh must not replace a host selection we do not own.
        if text.isEmpty && !hasMarkedText { refreshCandidates(); return }
        if !text.isEmpty && !hasMarkedText { markedStart = target.selectedRange().location }
        let marked = NSMutableAttributedString(string: text)
        if !preedit.isEmpty {
            marked.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                range: NSRange(location: 0, length: preedit.utf16.count))
        }
        let prefix = String(decoding: preedit.utf8.prefix(max(0, context.cursor)), as: UTF8.self)
        let cursor = preedit.isEmpty ? 0 : prefix.utf16.count
        target.setMarkedText(marked, selectionRange: NSRange(location: cursor, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        hasMarkedText = !text.isEmpty
        if !hasMarkedText { markedStart = nil }
        refreshCandidates()
    }
    @MainActor private func refreshCandidates() {
        guard active else { return }
        let context = rime?.context ?? RimeEngine.Context()
        let preedit = englishMode ? "" : context.preedit
        if !preedit.isEmpty, !context.candidates.isEmpty {
            panel?.setSelectionKeys([18, 19, 20, 21, 23, 22, 26].map { NSNumber(value: $0) })
            panel?.update()
            panel?.show(kIMKLocateCandidatesBelowHint)
        } else if composition.preview != nil {
            panel?.setSelectionKeys([])
            panel?.update()
            panel?.show(kIMKLocateCandidatesBelowHint)
        } else { panel?.hide() }
    }
    @MainActor private func requestTranslation(manual: Bool) {
        let settings = OfflineConfiguration.shared
        guard !settings.paused, manual || settings.automatic, rime?.context.preedit.isEmpty ?? true else { return }
        let source = composition.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source.count <= 600, manual || composition.completeSentence != nil else { return }
        imeDiagnostic("translation requested")
        let token = composition.revision
        let style = settings.style
        settings.status = "正在本机处理，不影响原文输入与发送…"
        generation?.cancel()
        generation = Task { @MainActor [weak self] in
            do {
                if !manual { try await Task.sleep(nanoseconds: 700_000_000) }
                try Task.checkCancellation()
                let result = try await OfflineTranslator.generate(WritingRequest(source: source, style: style))
                try Task.checkCancellation()
                guard let self, self.active, self.composition.acceptPreview(result, revision: token) else { return }
                // An asynchronous result must never write into the host field.
                guard !self.canInspectSource || self.ownedRange() != nil else { self.forgetSentence(); return }
                imeDiagnostic("preview ready")
                settings.status = settings.englishOutput && self.ownedRange() != nil
                    ? "英文已就绪 · Tab 采用；Return 保留原文" : "英文已就绪 · 点击英文候选看讲解"
                self.refreshCandidates()
            } catch {
                guard let self, self.active, self.composition.revision == token, !Task.isCancelled else { return }
                imeDiagnostic("translation failed: \(error.localizedDescription)")
                settings.status = error.localizedDescription
            }
        }
    }
    override func candidates(_ sender: Any!) -> [Any]! {
        MainActor.assumeIsolated {
            let context = rime?.context ?? RimeEngine.Context()
            if !englishMode, !context.preedit.isEmpty { return context.candidates }
            if let preview = composition.preview {
                return [NSAttributedString(string: preview.expression, attributes: [.foregroundColor: NSColor.secondaryLabelColor])]
            }
            return []
        }
    }
    override func candidateSelected(_ candidateString: NSAttributedString!) {
        MainActor.assumeIsolated {
            imeDiagnostic("candidateSelected received")
            guard let candidateString else { return }
            let context = rime?.context ?? RimeEngine.Context()
            if !englishMode, !context.preedit.isEmpty, let index = context.candidates.firstIndex(of: candidateString.string) {
                rime?.select(index)
                consumeCommit()
                refresh()
            } else if composition.preview?.expression == candidateString.string {
                if OfflineConfiguration.shared.englishOutput, ownedRange() != nil { adoptEnglish() }
                else if let preview = composition.preview {
                    panel?.update()
                    panel?.show(kIMKLocateCandidatesBelowHint)
                    panel?.showAnnotation(NSAttributedString(string: preview.expression + "\n\n" + preview.explanation))
                    imeDiagnostic("annotation shown")
                }
            }
        }
    }
    override func candidateSelectionChanged(_ candidateString: NSAttributedString!) {
        MainActor.assumeIsolated {
            guard let text = candidateString?.string else { return }
            let context = rime?.context ?? RimeEngine.Context()
            if !englishMode, !context.preedit.isEmpty, let index = context.candidates.firstIndex(of: text) {
                rime?.highlight(index)
            }
        }
    }
    override func menu() -> NSMenu! {
        MainActor.assumeIsolated {
            let menu = NSMenu(title: "句外")
            let translate = NSMenuItem(title: "翻译 / 改写当前句子", action: #selector(translateNow), keyEquivalent: "t")
            translate.keyEquivalentModifierMask = [.control, .option]
            translate.target = self
            menu.addItem(translate)
            let settings = NSMenuItem(title: "句外输入法设置…", action: #selector(openSettings), keyEquivalent: "")
            settings.target = self
            menu.addItem(settings)
            menu.addItem(.separator())
            let status = NSMenuItem(title: OfflineConfiguration.shared.status, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            return menu
        }
    }
    @objc private func translateNow() { MainActor.assumeIsolated { confirmPinyin(); refresh(); requestTranslation(manual: true) } }
    @objc private func openSettings() {
        MainActor.assumeIsolated {
            commitOriginal()
            SettingsWindow.shared.show()
        }
    }
}
