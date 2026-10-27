import SwiftUI
import AppKit

/// Uses NSTextView's real input context; no custom Pinyin or keyboard interception.
struct NativeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var edited: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let editor = scroll.documentView as! NSTextView
        editor.isRichText = false
        editor.allowsUndo = true
        editor.font = .systemFont(ofSize: 16)
        editor.drawsBackground = false
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.delegate = context.coordinator
        editor.string = text
        context.coordinator.reportHeight(editor)
        scroll.drawsBackground = false
        editor.setAccessibilityLabel("中文或英文输入区")
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let editor = scroll.documentView as? NSTextView { context.coordinator.reportHeight(editor) }
        guard let editor = scroll.documentView as? NSTextView, !editor.hasMarkedText(), editor.string != text else { return }
        context.coordinator.isProgrammaticEdit = true
        defer { context.coordinator.isProgrammaticEdit = false }
        let range = NSRange(location: 0, length: editor.string.utf16.count)
        editor.breakUndoCoalescing()
        if editor.shouldChangeText(in: range, replacementString: text) {
            editor.textStorage?.replaceCharacters(in: range, with: text)
            editor.didChangeText()
            editor.undoManager?.setActionName("句外替换")
            editor.breakUndoCoalescing()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        var isProgrammaticEdit = false
        private var lastMarked = false
        init(_ parent: NativeEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticEdit, let editor = notification.object as? NSTextView else { return }
            lastMarked = editor.hasMarkedText()
            parent.text = editor.string
            parent.edited(lastMarked)
            reportHeight(editor)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticEdit, let editor = notification.object as? NSTextView else { return }
            let marked = editor.hasMarkedText()
            // A composition commit can clear the mark without changing the string.
            if lastMarked && !marked {
                parent.text = editor.string
                parent.edited(false)
            }
            lastMarked = marked
        }
        func reportHeight(_ editor: NSTextView) {
            guard let manager = editor.layoutManager, let container = editor.textContainer else { return }
            manager.ensureLayout(for: container)
            let height = min(240, max(44, ceil(manager.usedRect(for: container).height + editor.textContainerInset.height * 2 + 4)))
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.parent.height - height) > 1 else { return }
                self.parent.height = height
            }
        }
    }
}
