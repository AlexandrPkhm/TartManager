import AppKit

/// Installs the bundled icon for Swift Package launches, which have no app Info.plist.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppIconSource.needsRuntimeIcon(bundleURL: Bundle.main.bundleURL) else { return }
        NSApplication.shared.applicationIconImage = AppIcon.image
    }

    /// Lets AppKit recreate the SwiftUI `WindowGroup` when the Dock reopens
    /// the app after its last window was closed.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        true
    }
}
