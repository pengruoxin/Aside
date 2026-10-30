import Foundation

/// A candidate range is not permission to replace: the client identity and
/// exact host substring must also match immediately before insertion.
public enum CommittedTextRange {
    public static func candidate(start: Int, utf16Length: Int, selection: NSRange, marked: NSRange) -> NSRange? {
        guard start >= 0, start != NSNotFound, utf16Length > 0, utf16Length <= Int.max - start,
              selection.location != NSNotFound, selection.length == 0,
              selection.location == start + utf16Length, marked.location == NSNotFound else { return nil }
        return NSRange(location: start, length: utf16Length)
    }
}
