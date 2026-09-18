import Testing
@testable import TartKit

@Suite struct SuspendReconcilerTests {
    func entry(_ name: String, running: Bool) -> VMEntry {
        VMEntry(name: name, source: "local", running: running,
                state: running ? "running" : "stopped",
                diskSize: 0, diskUsage: 0, accessed: nil)
    }

    @Test func runningEntryAfterRefreshConfirmsTheFailure() {
        // The defining case: only a post-refresh *confirmed still running*
        // VM turns a failed suspend into an error.
        #expect(SuspendReconciler.reconcile(.fresh(entry("vm-a", running: true)))
                == .runningConfirmed)
    }

    @Test func notRunningEntryAfterRefreshReconcilesAsSuccess() {
        // The VM reports suspended/stopped (the suspend won the race, or
        // the VM was stopped externally) — not an error.
        #expect(SuspendReconciler.reconcile(.fresh(entry("vm-a", running: false)))
                == .reconciledNotRunning)
    }

    @Test func absentEntryAfterRefreshReconcilesAsSuccess() {
        // The VM vanished from the list entirely (deleted externally).
        #expect(SuspendReconciler.reconcile(.fresh(nil)) == .reconciledNotRunning)
    }

    @Test func staleOrFailedRefreshIsUnknownAndNeverAnError() {
        // Nil/stale inventory must not masquerade as "not running"; the
        // decision is unknown and the caller suppresses.
        #expect(SuspendReconciler.reconcile(.stale) == .unknownState)
    }
}
