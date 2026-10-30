import Foundation

/// Merge only this input method's entries; preserve every other keyboard source.
public enum InputSourcePreferences {
    public static let bundleID = "io.github.pengruoxin.inputmethod.Aside"
    public static let modes = [bundleID + ".Chinese", bundleID + ".English"]

    public static func enablingAside(in existing: [[String: Any]]) -> [[String: Any]] {
        var result = existing
        let parent: [String: Any] = ["Bundle ID": bundleID, "InputSourceKind": "Keyboard Input Method"]
        if !result.contains(where: { ($0["Bundle ID"] as? String) == bundleID && ($0["InputSourceKind"] as? String) == "Keyboard Input Method" }) {
            result.append(parent)
        }
        for mode in modes {
            if !result.contains(where: { ($0["Bundle ID"] as? String) == bundleID && ($0["Input Mode"] as? String) == mode }) {
                result.append(["Bundle ID": bundleID, "InputSourceKind": "Input Mode", "Input Mode": mode])
            }
        }
        return result
    }
}
