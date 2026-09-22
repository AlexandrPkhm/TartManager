import AppKit

/// Controls whether Tart Manager is a regular Dock app or a menu-bar-only app.
/// The main window returns the app to regular mode; after it closes, the app
/// remains available through its menu-bar extra without a Dock icon.
@MainActor
final class ApplicationActivationPolicy {
    static let mainWindowSceneID = "main-window"

    private let setActivationPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void
    private let activate: @MainActor () -> Void

    init(
        setActivationPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = {
            _ = NSApplication.shared.setActivationPolicy($0)
        },
        activate: @escaping @MainActor () -> Void = {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    ) {
        self.setActivationPolicy = setActivationPolicy
        self.activate = activate
    }

    /// Removes Tart Manager from the Dock while keeping its menu-bar extra active.
    func mainWindowDidClose() {
        setActivationPolicy(.accessory)
    }

    /// Restores the Dock presence, creates the primary scene, and foregrounds it.
    func openMainWindow(_ open: () -> Void) {
        setActivationPolicy(.regular)
        open()
        activate()
    }
}
