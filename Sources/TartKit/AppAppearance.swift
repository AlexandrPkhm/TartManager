import Foundation

/// Persisted app appearance. System follows the Mac's current appearance.
public enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark
}
