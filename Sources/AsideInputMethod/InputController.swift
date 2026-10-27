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
    private var preferencesObserver: NSObjectProtocol?
    private lazy var panel: IMKCandidates? = {
        let panel = IMKCandidates(server: server(), panelType: kIMKSingleRowSteppingCandidatePanel)
        panel?.setAttributes([IMKCandidatesSendServerKeyEventFirst: NSNumber(value: true)])
        return panel
    }()

    override func recognizedEvents(_ sender: Any!) -> Int { Int(NSEvent.EventTypeMask.keyDown.rawValue) }

    override func activateServer(_ sender: Any!) {
        MainActor.assumeIsolated {
            if active { commitOriginal() }
            generation?.cancel()
            composition.reset()
            hasMarkedText = false
            target = sender as? IMKTextInput
            active = true
            if rime == nil { rime = RimeEngine() }
            rime?.clear()
            updateMode()
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
        guard let event, active, let client = sender as? IMKTextInput else { return false }
        if let target, (target as AnyObject) !== (client as AnyObject) {
            commitOriginal()
            composition.reset()
        }
        target = client
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
            adoptEnglish()
            return true
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
                if let rime, rime.process(0xff0d) {
                    consumeCommit(); refresh()
                } else { confirmPinyin(); refresh() }
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
            composition.backspace()
            refresh()
            return true
        }
        guard let chars = event.characters, !chars.isEmpty else { return false }
        let functionKey = chars.unicodeScalars.contains { (0xF700...0xF8FF).contains($0.value) }
        if functionKey && !composingPinyin {
            commitOriginal()
            return false
        }
        if composition.preview != nil {
            // New typing starts a new sentence; only the original is committed.
            commitOriginal()
        }
        if !englishMode, let rime, rime.available {
            let special: [UInt16: Int32] = [123: 0xff51, 124: 0xff53, 125: 0xff54, 126: 0xff52, 116: 0xff55, 121: 0xff56, 117: 0xffff]
            let value = special[event.keyCode] ?? chars.unicodeScalars.first.map { Int32($0.value) } ?? 0
            if rime.process(value, modifiers: flags.contains(.shift) ? 1 : 0) {
                consumeCommit()
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
        composition.append(text)
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
        if let text = rime?.takeCommit(), !text.isEmpty { composition.append(text) }
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
        let original = composition.takeOriginal()
        panel?.hide()
        if !original.isEmpty {
            target?.insertText(original, replacementRange: NSRange(location: NSNotFound, length: 0))
        } else if hasMarkedText {
            target?.setMarkedText("", selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        hasMarkedText = false
    }
    @MainActor private func adoptEnglish() {
        generation?.cancel()
        guard let text = composition.takeEnglish() else { return }
        rime?.clear()
        panel?.hide()
        target?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        hasMarkedText = false
    }
    @MainActor private func refresh() {
        guard active, let target else { return }
        let context = rime?.context ?? RimeEngine.Context()
        let preedit = englishMode ? "" : context.preedit
        let text = composition.hostMarkedText(preedit: preedit)
        let marked = NSMutableAttributedString(string: text)
        if !preedit.isEmpty {
            marked.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                range: NSRange(location: composition.source.utf16.count, length: preedit.utf16.count))
        }
        let prefix = String(decoding: preedit.utf8.prefix(max(0, context.cursor)), as: UTF8.self)
        let cursor = composition.source.utf16.count + (preedit.isEmpty ? 0 : prefix.utf16.count)
        target.setMarkedText(marked, selectionRange: NSRange(location: cursor, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        hasMarkedText = !text.isEmpty
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
                settings.status = settings.englishOutput ? "英文已就绪 · Tab 采用；Return 保留原文" : "英文已就绪 · 点击英文候选看讲解"
                self.refresh()
            } catch {
                guard let self, self.active, self.composition.revision == token, !Task.isCancelled else { return }
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
            guard let candidateString else { return }
            let context = rime?.context ?? RimeEngine.Context()
            if !englishMode, !context.preedit.isEmpty, let index = context.candidates.firstIndex(of: candidateString.string) {
                rime?.select(index)
                consumeCommit()
                refresh()
            } else if composition.preview?.expression == candidateString.string {
                if OfflineConfiguration.shared.englishOutput { adoptEnglish() }
                else if let explanation = composition.preview?.explanation {
                    panel?.showAnnotation(NSAttributedString(string: explanation))
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
