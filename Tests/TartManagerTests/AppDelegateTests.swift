import AppKit
import Testing
@testable import TartManager

@Suite @MainActor struct AppDelegateTests {
    @Test func reopenWithoutVisibleWindowsRestoresTheMainWindow() {
        let delegate: NSApplicationDelegate = AppDelegate()

        let shouldRestore = delegate.applicationShouldHandleReopen?(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        #expect(shouldRestore == true)
    }
}
