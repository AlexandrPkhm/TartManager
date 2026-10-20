import AppKit
import os
import TartKit

/// Controls whether Tart Manager is a regular Dock app or a menu-bar-only app.
/// The main window returns the app to regular mode; after the last main
/// window closes, the app remains available through its menu-bar extra
/// without a Dock icon.
///
/// It also answers Dock reopen events (issue #5). A reopen in menu-bar-only
/// mode has no SwiftUI view that can call `openWindow`, so views register an
/// opener here and the app delegate asks this policy what to do.
@MainActor
final class ApplicationActivationPolicy {
    static let mainWindowSceneID = "main-window"

    private let setActivationPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void
    private let activate: @MainActor () -> Void
    private let scheduleReopenCheck: @MainActor (@escaping @MainActor () -> Bool) -> Void

    /// Main windows on screen now. `hasVisibleWindows` from AppKit cannot
    /// replace this count: it is `true` when only Settings is open.
    private(set) var openMainWindowCount = 0
    /// Every main-window appearance since launch; a reopen check compares it.
    private var mainWindowOpenEvents = 0
    private var mainWindowOpener: (@MainActor () -> Void)?

    init(
        setActivationPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = {
            _ = NSApplication.shared.setActivationPolicy($0)
        },
        activate: @escaping @MainActor () -> Void = {
            NSApplication.shared.activate(ignoringOtherApps: true)
        },
        scheduleReopenCheck: @escaping @MainActor (@escaping @MainActor () -> Bool) -> Void = { check in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                _ = check()
            }
        }
    ) {
        self.setActivationPolicy = setActivationPolicy
        self.activate = activate
        self.scheduleReopenCheck = scheduleReopenCheck
    }

    /// Records a main window that appeared.
    func mainWindowDidOpen() {
        openMainWindowCount += 1
        mainWindowOpenEvents += 1
    }

    /// Records a main window that closed. Removes Tart Manager from the Dock,
    /// while keeping its menu-bar extra active, only when no main window
    /// remains.
    func mainWindowDidClose() {
        if openMainWindowCount == 0 {
            Logger.window.warning("Main window closed with no open main window recorded")
        }
        openMainWindowCount = max(0, openMainWindowCount - 1)
        guard openMainWindowCount == 0 else {
            Logger.window.info("Main window closed; \(self.openMainWindowCount, privacy: .public) still open, Dock icon kept")
            return
        }
        setActivationPolicy(.accessory)
    }

    /// Stores the action that creates a main-window scene. The latest
    /// registration wins.
    func registerMainWindowOpener(_ open: @escaping @MainActor () -> Void) {
        mainWindowOpener = open
    }

    /// Restores the Dock presence, creates the primary scene, and foregrounds it.
    func openMainWindow(_ open: () -> Void) {
        setActivationPolicy(.regular)
        open()
        activate()
    }

    /// Answers `applicationShouldHandleReopen(_:hasVisibleWindows:)`.
    ///
    /// - Returns: `true` to let AppKit bring an open or minimized main window
    ///   forward, `false` when this policy opened a new main window itself.
    func handleReopen() -> Bool {
        guard openMainWindowCount == 0 else {
            Logger.window.info("Reopen: \(self.openMainWindowCount, privacy: .public) main windows open; AppKit restores them")
            return true
        }
        guard let opener = mainWindowOpener else {
            Logger.window.error("Reopen: no main-window opener registered; main window not restored")
            return true
        }
        Logger.window.info("Reopen in menu-bar-only mode: opening the main window")
        let openEventsBefore = mainWindowOpenEvents
        openMainWindow(opener)
        scheduleReopenCheck { [weak self] in
            guard let self else { return true }
            let opened = self.mainWindowOpenEvents > openEventsBefore
            if !opened {
                Logger.window.error("Reopen: the opener ran but no main window appeared")
            }
            return opened
        }
        return false
    }
}
