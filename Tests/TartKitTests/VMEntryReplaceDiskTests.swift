import Testing
@testable import TartKit

@Suite struct VMEntryReplaceDiskTests {
    func entry(running: Bool, state: String) -> VMEntry {
        VMEntry(name: "vm-a", source: "local", running: running, state: state,
                diskSize: 80, diskUsage: 75, accessed: nil)
    }

    @Test func stoppedVMCanReplaceItsDisk() {
        #expect(entry(running: false, state: "stopped").canReplaceDisk)
    }

    @Test func runningVMCanNotReplaceItsDisk() {
        #expect(!entry(running: true, state: "running").canReplaceDisk)
    }

    @Test func suspendedVMCanNotReplaceItsDiskRegardlessOfCase() {
        // Finding 1: a suspended row (running == false, state suspended) must
        // never land on the replace path.
        #expect(!entry(running: false, state: "suspended").canReplaceDisk)
        #expect(!entry(running: false, state: "SUSPENDED").canReplaceDisk)
    }
}
