public enum WritingOrigin {
    case editor, selection, automatic
    public var isExternal: Bool { self != .editor }
    public var discardWhenAutomaticContextIsLost: Bool { self == .automatic }
}
