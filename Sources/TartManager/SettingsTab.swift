import CoreGraphics

/// The Settings tabs, in display order. `AppModel` owns the selection so
/// **About Tart Manager** and the title-bar update button can open a tab.
enum SettingsTab: Hashable {
    case general
    case storage
    case about

    /// The Settings window content height for this tab, at the 640 pt
    /// width. Storage and About fit their content without scrolling. General
    /// uses the Storage height, so switching between them does not resize
    /// the window, and its `SettingsPage` scrolls.
    var frameHeight: CGFloat {
        switch self {
        case .general: return Self.storage.frameHeight
        case .storage: return 514
        case .about: return 471
        }
    }
}
