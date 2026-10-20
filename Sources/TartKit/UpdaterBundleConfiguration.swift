import Foundation

/// Checks that the app bundle carries the keys Sparkle needs. A `swift run`
/// binary has no bundle `Info.plist`, so the updater must not start there.
public enum UpdaterBundleConfiguration {
    /// The `Info.plist` keys without which Sparkle cannot check or verify.
    public static let requiredKeys = ["SUFeedURL", "SUPublicEDKey"]

    /// Returns the required keys that are absent, blank, or not strings, in
    /// `requiredKeys` order.
    public static func missingKeys(in info: [String: Any]?) -> [String] {
        requiredKeys.filter { key in
            guard let value = info?[key] as? String else { return true }
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
