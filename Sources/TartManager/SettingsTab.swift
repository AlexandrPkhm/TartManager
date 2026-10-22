import CoreGraphics

/// The Settings tabs, in display order. `AppModel` owns the selection so
/// **About Tart Manager** and the title-bar update button can open a tab.
enum SettingsTab: Hashable {
    case general
    case storage
    case about

    /// The Settings window content height for this tab. Each value fits
    /// the tab's content at the 640 pt width without scrolling.
    var frameHeight: CGFloat {
        switch self {
        case .general: return 740
        case .storage: return 514
        case .about: return 471
        }
    }
}
