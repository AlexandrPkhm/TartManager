import Testing
import Foundation
@testable import TartKit

@Suite struct VMEntrySuspensionTests {
    func entry(_ state: String, running: Bool = true) -> VMEntry {
        VMEntry(name: "vm-a", source: "local", running: running, state: state,
                diskSize: 0, diskUsage: 0, accessed: nil)
    }

    func decodeOne(_ json: String) throws -> VMEntry {
        // The samples are single rows; `tart list --format json` emits an
        // array, so wrap the row before decoding as the list shape.
        try JSONDecoder().decode([VMEntry].self, from: Data("[\(json)]".utf8))[0]
    }

    @Test func suspendedStateNormalizesToNotRunningAtDecode() throws {
        // Even when tart's `Running` field stays true for a suspended VM
        // (the outcome Task 0 records), the state machine says suspended
        // is not running — every row branch, pre-check, and the run
        // registry's reconcile eviction key on `running`.
        let suspended = try decodeOne(#"""
        {"Name":"vm-a","Source":"local","Running":true,"State":"suspended","Disk":35,"Size":0}
        """#)
        #expect(suspended.running == false)
        #expect(suspended.isSuspended)
    }

    @Test func runningStateStillDecodesAsRunning() throws {
        let running = try decodeOne(#"""
        {"Name":"vm-a","Source":"local","Running":true,"State":"running","Disk":35,"Size":0}
        """#)
        #expect(running.running)
        #expect(!running.isSuspended)
    }

    @Test func isSuspendedMatchesTheSpikeLiteralCaseInsensitively() {
        #expect(entry("suspended").isSuspended)
        #expect(entry("SUSPENDED").isSuspended)
        #expect(!entry("stopped").isSuspended)
        #expect(!entry("running").isSuspended)
    }

    @Test func suspendedRowGetsResumeLabelWhenTartDistinguishes() {
        #expect(entry("suspended", running: false)
            .primaryActionLabel(distinguishesSuspended: true) == "Resume")
    }

    @Test func stoppedRowGetsRunLabelWhenTartDistinguishes() {
        #expect(entry("stopped", running: false)
            .primaryActionLabel(distinguishesSuspended: true) == "Run")
    }

    @Test func fallbackOffersResumeOnBothPerTheIssue() {
        // PRD Open Question fallback: treat suspended as stopped and offer
        // Resume on both — a stopped row may hide a parked session.
        #expect(entry("stopped", running: false)
            .primaryActionLabel(distinguishesSuspended: false) == "Resume")
        #expect(entry("suspended", running: false)
            .primaryActionLabel(distinguishesSuspended: false) == "Resume")
    }

    /// The single delete/rename predicate: stopped local VMs only. Reuses
    /// `isSuspended` — suspended entries (even memberwise-constructed with
    /// running == false) are not deletable/renamable, per US 19/20 AC2.
    @Test func stoppedLocalPredicateGatesDeleteAndRename() {
        #expect(entry("stopped", running: false).isStoppedLocal)
        #expect(!entry("running", running: true).isStoppedLocal)
        #expect(!entry("suspended", running: false).isStoppedLocal)
        let oci = VMEntry(name: "img:1", source: "oci", running: false, state: "stopped",
                          diskSize: 0, diskUsage: 0, accessed: nil)
        #expect(!oci.isStoppedLocal)
    }
}
