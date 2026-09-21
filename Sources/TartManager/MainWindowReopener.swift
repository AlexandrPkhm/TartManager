import AppKit

/// Recreates the primary SwiftUI window after the Dock activates an app that
/// has no visible windows. SwiftUI does not reliably forward that Dock event
/// through an `NSApplicationDelegateAdaptor`, so this observes activation
/// directly and invokes the scene's `OpenWindowAction` instead.
@MainActor
final class MainWindowReopener {
    static let mainWindowSceneID = "main-window"

    private let notificationCenter: NotificationCenter
    private let hasVisibleWindows: @MainActor () -> Bool
    private var activationObserver: NSObjectProtocol?
    private var openMainWindow: (() -> Void)?

    init(
        notificationCenter: NotificationCenter = .default,
        hasVisibleWindows: (@MainActor () -> Bool)? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.hasVisibleWindows = hasVisibleWindows ?? {
            NSApplication.shared.windows.contains { $0.isVisible }
        }
        activationObserver = notificationCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationActivation()
            }
        }
    }

    deinit {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
    }

    /// Registers the scene action after the primary window first appears.
    func register(openMainWindow: @escaping () -> Void) {
        self.openMainWindow = openMainWindow
    }

    func handleApplicationActivation() {
        guard !hasVisibleWindows() else { return }
        openMainWindow?()
    }
}
