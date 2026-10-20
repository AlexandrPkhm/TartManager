import AppKit

/// Owns the activation policy and answers AppKit application events: it
/// installs the bundled icon for Swift Package launches, which have no app
/// Info.plist, and restores the main window on a Dock reopen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let applicationActivationPolicy = ApplicationActivationPolicy()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard AppIconSource.needsRuntimeIcon(bundleURL: Bundle.main.bundleURL) else { return }
        NSApplication.shared.applicationIconImage = AppIcon.image
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        applicationActivationPolicy.handleReopen()
    }
}
