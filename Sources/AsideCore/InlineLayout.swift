import Foundation

/// Screen-space geometry only. Never changes host text or moves its caret.
public enum InlineLayout {
    public static func frame(field: CGRect, caret: CGRect, visible: CGRect) -> CGRect? {
        nil // RED: empty implementation to prove boundary tests fail before rendering.
    }
}
