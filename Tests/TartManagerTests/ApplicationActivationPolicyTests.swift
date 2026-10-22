import AppKit
import Testing
@testable import TartManager

@Suite @MainActor struct ApplicationActivationPolicyTests {
    /// Records policy changes, activations, opener calls, and scheduled
    /// reopen checks in the order they happen.
    @MainActor final class Recorder {
        var events: [String] = []
        var reopenChecks: [@MainActor () -> Bool] = []

        func makePolicy() -> ApplicationActivationPolicy {
            ApplicationActivationPolicy(
                setActivationPolicy: { [unowned self] policy in
                    events.append(policy == .regular ? "regular" : "accessory")
                },
                activate: { [unowned self] in events.append("activate") },
                scheduleReopenCheck: { [unowned self] check in reopenChecks.append(check) }
            )
        }
    }

    @Test func closingTheMainWindowSwitchesToMenuBarOnlyMode() {
        let recorder = Recorder()
        let policy = recorder.makePolicy()

        policy.mainWindowDidClose()

        #expect(recorder.events == ["accessory"])
    }

    @Test func openingFromTheMenuRestoresTheDockBeforeOpeningTheWindow() {
        let recorder = Recorder()
        let policy = recorder.makePolicy()

        policy.openMainWindow { recorder.events.append("open") }

        #expect(recorder.events == ["regular", "open", "activate"])
    }

    @Test func closingOneOfTwoMainWindowsKeepsTheDockIcon() {
        let recorder = Recorder()
        let policy = recorder.makePolicy()
        policy.mainWindowDidOpen()
        policy.mainWindowDidOpen()

        policy.mainWindowDidClose()

        #expect(recorder.events.isEmpty)
        #expect(policy.openMainWindowCount == 1)
    }

    @Test func closingTheLastOfTwoMainWindowsSwitchesToMenuBarOnlyMode() {
        let recorder = Recorder()
        let policy = recorder.makePolicy()
        policy.mainWindowDidOpen()
        policy.mainWindowDidOpen()

        policy.mainWindowDidClose()
        policy.mainWindowDidClose()

        #expect(recorder.events == ["accessory"])
        #expect(policy.openMainWindowCount == 0)
    }

    @Test func reopenWithAnOpenMainWindowLetsAppKitRestoreIt() {
        let recorder = Recorder()
        let policy = recorder.makePolicy()
        policy.registerMainWindowOpener { recorder.events.append("open") }
        policy.mainWindowDidOpen()

        let handledByAppKit = policy.handleReopen()

        #expect(handledByAppKit)
        #expect(recorder.events.isEmpty)
        #expect(recorder.reopenChecks.isEmpty)
    }

    @Test func reopenInMenuBarOnlyModeOpensTheMainWindow() {
        let recorder = Recorder()
        let policy = recorder.makePolicy()
        policy.registerMainWindowOpener { recorder.events.append("open") }
        policy.mainWindowDidOpen()
        policy.mainWindowDidClose()
        recorder.events.removeAll()

        let handledByAppKit = policy.handleReopen()

        #expect(!handledByAppKit)
        #expect(recorder.events == ["regular", "open", "activate"])
    }

    @Test func reopenWithOnlySettingsOpenStillOpensTheMainWindow() {
        // AppKit reports hasVisibleWindows == true here; the policy ignores it.
        let recorder = Recorder()
        let policy = recorder.makePolicy()
        policy.registerMainWindowOpener { recorder.events.append("open") }

        let handledByAppKit = policy.handleReopen()

        #expect(!handledByAppKit)
        #expect(recorder.events == ["regular", "open", "activate"])
    }

    @Test func reopenWithoutAnOpenerLeavesThePolicyUnchanged() {
        let recorder = Recorder()
        let policy = recorder.makePolicy()

        let handledByAppKit = policy.handleReopen()

        #expect(handledByAppKit)
        #expect(recorder.events.isEmpty)
        #expect(recorder.reopenChecks.isEmpty)
    }

    @Test func reopenUsesTheLatestRegisteredOpener() {
        let recorder = Recorder()
        let policy = recorder.makePolicy()
        policy.registerMainWindowOpener { recorder.events.append("first") }
        policy.registerMainWindowOpener { recorder.events.append("second") }

        _ = policy.handleReopen()

        #expect(recorder.events == ["regular", "second", "activate"])
    }

    @Test func reopenCheckPassesWhenTheMainWindowAppears() throws {
        let recorder = Recorder()
        let policy = recorder.makePolicy()
        policy.registerMainWindowOpener { policy.mainWindowDidOpen() }

        _ = policy.handleReopen()

        let check = try #require(recorder.reopenChecks.first)
        #expect(recorder.reopenChecks.count == 1)
        #expect(check())
    }

    @Test func reopenCheckFailsWhenNoMainWindowAppears() throws {
        let recorder = Recorder()
        let policy = recorder.makePolicy()
        policy.registerMainWindowOpener {}

        _ = policy.handleReopen()

        let check = try #require(recorder.reopenChecks.first)
        #expect(!check())
    }
}
