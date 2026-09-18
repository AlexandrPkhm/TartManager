import Testing
@testable import TartKit

@Suite struct RestoreGateTests {
    @Test func exactMatchAllowsProceed() {
        #expect(RestoreGate.allowsProceed(typedName: "vm-a", vmName: "vm-a"))
    }

    @Test func caseMismatchIsRefused() {
        #expect(!RestoreGate.allowsProceed(typedName: "VM-A", vmName: "vm-a"))
        #expect(!RestoreGate.allowsProceed(typedName: "Vm-A", vmName: "vm-a"))
    }

    @Test func whitespaceDifferenceIsRefused() {
        #expect(!RestoreGate.allowsProceed(typedName: "vm-a ", vmName: "vm-a"))
        #expect(!RestoreGate.allowsProceed(typedName: " vm-a", vmName: "vm-a"))
    }

    @Test func emptyAndPartialNamesAreRefused() {
        #expect(!RestoreGate.allowsProceed(typedName: "", vmName: "vm-a"))
        #expect(!RestoreGate.allowsProceed(typedName: "vm", vmName: "vm-a"))
    }
}
