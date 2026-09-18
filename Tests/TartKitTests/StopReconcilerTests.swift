import Testing
@testable import TartKit

@Suite struct StopReconcilerTests {
    func entry(_ name: String, running: Bool) -> VMEntry {
        VMEntry(name: name, source: "local", running: running,
                state: running ? "running" : "stopped",
                diskSize: 0, diskUsage: 0, accessed: nil)
    }

    @Test func runningEntryAfterRefreshConfirmsTheFailure() {
        // The defining case: only a post-refresh *confirmed still running*
        // VM turns a failed stop into an error.
        #expect(StopReconciler.reconcile(.fresh(entry("vm-a", running: true)))
                == .runningConfirmed)
    }

    @Test func stoppedEntryAfterRefreshReconcilesAsSuccess() {
        // Window closed / terminal stop raced us — not an error.
        #expect(StopReconciler.reconcile(.fresh(entry("vm-a", running: false)))
                == .reconciledStopped)
    }

    @Test func absentEntryAfterRefreshReconcilesAsSuccess() {
        // The VM vanished from the list entirely (deleted externally).
        #expect(StopReconciler.reconcile(.fresh(nil)) == .reconciledStopped)
    }

    @Test func staleOrFailedRefreshIsUnknownAndNeverAnError() {
        // Nil/stale inventory must not masquerade as "not running";
        // the decision is unknown and the caller suppresses.
        #expect(StopReconciler.reconcile(.stale) == .unknownState)
    }
}
