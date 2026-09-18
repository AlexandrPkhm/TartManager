import Testing
import Foundation
@testable import TartKit

@Suite struct VMEntryEditabilityTests {
    func entry(running: Bool, state: String) -> VMEntry {
        VMEntry(name: "vm-a", source: "local", running: running, state: state,
                diskSize: 80, diskUsage: 75, accessed: nil)
    }

    @Test func stoppedVMIsEditable() {
        #expect(entry(running: false, state: "stopped").canEditResources)
    }

    @Test func runningVMIsNotEditable() {
        #expect(!entry(running: true, state: "running").canEditResources)
    }

    @Test func suspendedVMIsNotEditableRegardlessOfCase() {
        #expect(!entry(running: false, state: "suspended").canEditResources)
        #expect(!entry(running: false, state: "SUSPENDED").canEditResources)
    }
}
