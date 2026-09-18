import Testing
@testable import TartKit

@Suite struct ReplaceDiskGuardTests {
    func entry(_ name: String = "vm-a", source: String = "local",
               running: Bool = false, state: String = "stopped") -> VMEntry {
        VMEntry(name: name, source: source, running: running, state: state,
                diskSize: 80, diskUsage: 75, accessed: nil)
    }

    @Test func confirmedStoppedLocalVMPasses() {
        #expect(ReplaceDiskGuard.refusal(vm: entry(), typedName: "vm-a",
                                         path: "/images/clean.img") == nil)
    }

    @Test func typedNameMismatchFailsTheGate() {
        // The issue's automated check: the typed-name gate must pass before
        // any CLI call. Case, whitespace, and partial names all refuse.
        #expect(ReplaceDiskGuard.refusal(vm: entry(), typedName: "VM-A",
                                         path: "/images/clean.img") == .gateFailed)
        #expect(ReplaceDiskGuard.refusal(vm: entry(), typedName: "vm-a ",
                                         path: "/images/clean.img") == .gateFailed)
        #expect(ReplaceDiskGuard.refusal(vm: entry(), typedName: "vm",
                                         path: "/images/clean.img") == .gateFailed)
        #expect(ReplaceDiskGuard.refusal(vm: entry(), typedName: "vm-a",
                                         path: "") == .gateFailed)
    }

    @Test func runningAndSuspendedVMsAreRefused() {
        // The issue's automated check: stopped-only enforcement at the
        // model layer (finding 1: suspended is refused explicitly).
        #expect(ReplaceDiskGuard.refusal(vm: entry(running: true, state: "running"),
                                         typedName: "vm-a",
                                         path: "/images/clean.img") == .running)
        #expect(ReplaceDiskGuard.refusal(vm: entry(state: "suspended"),
                                         typedName: "vm-a",
                                         path: "/images/clean.img") == .suspended)
        #expect(ReplaceDiskGuard.refusal(vm: entry(state: "SUSPENDED"),
                                         typedName: "vm-a",
                                         path: "/images/clean.img") == .suspended)
    }

    @Test func ociEntriesAreRefusedAsNotLocal() {
        // Finding 5: the model-layer guard mirrors Issue 17's isLocal-first
        // shape even though the UI cannot reach it for OCI rows today.
        #expect(ReplaceDiskGuard.refusal(vm: entry(source: "OCI"),
                                         typedName: "vm-a",
                                         path: "/images/clean.img") == .notLocal)
    }

    @Test func lossWarningPayloadNamesTheVMAndTheLoss() {
        // The issue's automated check: red-warning payload presence, verbatim.
        let warning = ReplaceDiskCopy.lossWarning(for: "vm-a")
        #expect(warning.contains("“vm-a”"))
        #expect(warning.contains("current disk contents"))
        #expect(warning.contains("will be lost"))
        #expect(warning.contains("files, apps, and settings"))
    }

    @Test func refusalMessagesAreVerboseAndActionable() {
        // Finding 5: every refusal has a presented, non-silent message.
        #expect(ReplaceDiskCopy.refusalMessage(for: .running, vmName: "vm-a")
            .contains("running"))
        #expect(ReplaceDiskCopy.refusalMessage(for: .suspended, vmName: "vm-a")
            .contains("resume and stop"))
        #expect(ReplaceDiskCopy.refusalMessage(for: .notLocal, vmName: "vm-a")
            .contains("local VMs"))
        #expect(ReplaceDiskCopy.refusalMessage(for: .gateFailed, vmName: "vm-a")
            .contains("not confirmed"))
        #expect(ReplaceDiskCopy.refusalMessage(for: .inFlight, vmName: "vm-a")
            .contains("already in progress"))
    }
}
