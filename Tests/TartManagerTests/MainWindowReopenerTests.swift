import Foundation
import Testing
@testable import TartManager

@Suite @MainActor struct MainWindowReopenerTests {
    @Test func activationWithoutVisibleWindowsOpensTheMainWindow() {
        var openCount = 0
        let reopener = MainWindowReopener(
            notificationCenter: NotificationCenter(),
            hasVisibleWindows: { false }
        )
        reopener.register { openCount += 1 }

        reopener.handleApplicationActivation()

        #expect(openCount == 1)
    }

    @Test func activationWithVisibleWindowsDoesNotOpenAnotherMainWindow() {
        var openCount = 0
        let reopener = MainWindowReopener(
            notificationCenter: NotificationCenter(),
            hasVisibleWindows: { true }
        )
        reopener.register { openCount += 1 }

        reopener.handleApplicationActivation()

        #expect(openCount == 0)
    }
}
