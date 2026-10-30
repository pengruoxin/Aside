import Foundation

/// The source is the only text allowed into the host. Learning previews are separate.
public struct SentenceComposition {
    public private(set) var source = ""
    public private(set) var preview: WritingResult?
    public private(set) var revision = UUID()
    public init() {}
    public var completeSentence: String? { SentencePolicy.completed(source) }
    public mutating func append(_ text: String) {
        source += text
        invalidate()
    }
    public mutating func backspace() {
        if !source.isEmpty { source.removeLast() }
        invalidate()
    }
    public mutating func invalidate() {
        revision = UUID()
        preview = nil
    }
    @discardableResult public mutating func acceptPreview(_ value: WritingResult, revision: UUID) -> Bool {
        guard self.revision == revision, !source.isEmpty else { return false }
        preview = value
        return true
    }
    /// Confirmed source is already in the host; only unfinished pinyin is marked.
    public func hostMarkedText(preedit: String) -> String { preedit }
    /// A rewrite owns the sentence, not its spacing relative to surrounding text.
    public var englishReplacement: String? {
        guard let preview, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let leading = source.prefix(while: { $0.isWhitespace })
        let trailing = String(source.reversed().prefix(while: { $0.isWhitespace }).reversed())
        return String(leading) + preview.expression + trailing
    }
    public mutating func takeOriginal() -> String {
        let text = source
        reset()
        return text
    }
    public mutating func takeEnglish() -> String? {
        guard let text = englishReplacement else { return nil }
        reset()
        return text
    }
    public mutating func reset() { source = ""; invalidate() }
}
