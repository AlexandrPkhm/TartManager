import Testing
@testable import TartKit

@Suite struct TypedConfirmationGateTests {
    @Test func exactMatchAllowsProceed() {
        #expect(TypedConfirmationGate.allowsProceed(typedName: "vm-a", vmName: "vm-a"))
    }

    @Test func caseMismatchIsRefused() {
        #expect(!TypedConfirmationGate.allowsProceed(typedName: "VM-A", vmName: "vm-a"))
        #expect(!TypedConfirmationGate.allowsProceed(typedName: "Vm-A", vmName: "vm-a"))
    }

    @Test func whitespaceDifferenceIsRefused() {
        #expect(!TypedConfirmationGate.allowsProceed(typedName: "vm-a ", vmName: "vm-a"))
        #expect(!TypedConfirmationGate.allowsProceed(typedName: " vm-a", vmName: "vm-a"))
    }

    @Test func emptyAndPartialNamesAreRefused() {
        #expect(!TypedConfirmationGate.allowsProceed(typedName: "", vmName: "vm-a"))
        #expect(!TypedConfirmationGate.allowsProceed(typedName: "vm", vmName: "vm-a"))
    }
}
