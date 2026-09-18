import Testing
@testable import TartKit

@Suite struct CloneGuardTests {
    @Test func validNamesPass() {
        #expect(CloneGuard.validateName("vm-from-golden", taken: []) == nil)
        #expect(CloneGuard.validateName("vm-2", taken: []) == nil) // inner hyphen is fine
        #expect(CloneGuard.validateName("x64", taken: []) == nil)
    }

    @Test func emptyNameIsRefused() {
        #expect(CloneGuard.validateName("", taken: []) == .empty)
    }

    @Test func pathSeparatorsAndTraversalAreRefused() {
        // Finding 5: a name with a path separator or ".." could land the
        // clone outside the storage root — rejected up front.
        #expect(CloneGuard.validateName("a/b", taken: []) == .invalidSyntax)
        #expect(CloneGuard.validateName("a\\b", taken: []) == .invalidSyntax)
        #expect(CloneGuard.validateName("..", taken: []) == .invalidSyntax)
        #expect(CloneGuard.validateName(".", taken: []) == .invalidSyntax)
    }

    @Test func leadingDashIsRefusedAsAFlag() {
        // Finding 5: a leading "-" would be misparsed as a CLI flag.
        #expect(CloneGuard.validateName("-vm", taken: []) == .invalidSyntax)
    }

    @Test func takenNameIsRefused() {
        #expect(CloneGuard.validateName("vm-a", taken: ["vm-a"]) == .taken)
        #expect(CloneGuard.validateName("vm-a", taken: []) == nil)
    }

    @Test func sourceValidationDistinguishesLocalAndRunning() {
        func entry(_ name: String, source: String = "local", running: Bool = false) -> VMEntry {
            VMEntry(name: name, source: source, running: running,
                    state: running ? "running" : "stopped",
                    diskSize: 0, diskUsage: 0, accessed: nil)
        }
        #expect(CloneGuard.validateSource(entry("vm-a")) == nil)
        #expect(CloneGuard.validateSource(entry("vm-a", running: true)) == .running)
        #expect(CloneGuard.validateSource(entry("img", source: "OCI")) == .notLocal)
    }
}
