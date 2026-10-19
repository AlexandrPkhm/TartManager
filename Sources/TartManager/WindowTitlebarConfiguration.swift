import AppKit

/// The main-window title-bar settings and geometry.
enum WindowTitlebarConfiguration {
    /// The unified title-bar height that AppKit uses on macOS 14 and later.
    /// The top row uses it until the window reports its own value.
    static let defaultHeight: CGFloat = 52

    /// Keeps the native window controls, hides the title text, and lets the
    /// SwiftUI top row draw under a transparent, unified title bar.
    static func apply(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "app.TartManager.mainWindow")
            toolbar.showsBaselineSeparator = false
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unified
    }

    /// The window title-bar height, or `defaultHeight` when the window shows
    /// no title bar, for example in full screen.
    static func titlebarHeight(of window: NSWindow) -> CGFloat {
        let height = window.frame.height - window.contentLayoutRect.height
        return resolvedHeight(height)
    }

    /// Replaces a missing or non-finite title-bar height with `defaultHeight`.
    static func resolvedHeight(_ height: CGFloat) -> CGFloat {
        height.isFinite && height > 0 ? height : defaultHeight
    }
}
