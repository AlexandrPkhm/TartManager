import AppKit

/// Installs the bundled icon for Swift Package launches, which have no app Info.plist.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = AppIcon.image
    }
}
