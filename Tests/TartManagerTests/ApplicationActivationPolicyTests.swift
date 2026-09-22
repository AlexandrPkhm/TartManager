import AppKit
import Testing
@testable import TartManager

@Suite @MainActor struct ApplicationActivationPolicyTests {
    @Test func closingTheMainWindowSwitchesToMenuBarOnlyMode() {
        var policies: [NSApplication.ActivationPolicy] = []
        let policy = ApplicationActivationPolicy(
            setActivationPolicy: { policies.append($0) },
            activate: {}
        )

        policy.mainWindowDidClose()

        #expect(policies == [.accessory])
    }

    @Test func openingFromTheMenuRestoresTheDockBeforeOpeningTheWindow() {
        var events: [String] = []
        let policy = ApplicationActivationPolicy(
            setActivationPolicy: { policy in
                events.append(policy == .regular ? "regular" : "accessory")
            },
            activate: { events.append("activate") }
        )

        policy.openMainWindow { events.append("open") }

        #expect(events == ["regular", "open", "activate"])
    }
}
