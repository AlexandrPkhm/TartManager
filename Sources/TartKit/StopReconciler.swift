import Foundation

/// What the inventory tells us about a VM after the post-failure refresh.
public enum PostStopInventory: Equatable, Sendable {
    /// A fetch completed after the failed stop attempt. The associated entry
    /// is the VM's current listing, or nil when it vanished from the list.
    case fresh(VMEntry?)
    /// The refresh failed or never ran (skipped by the in-flight guard):
    /// nothing trustworthy to conclude from.
    case stale
}

/// The decision for a failed stop command (the issue's defining rule).
public enum StopReconciliation: Equatable, Sendable {
    case reconciledStopped   // VM gone/stopped — success, no error
    case runningConfirmed    // VM confirmed still running — surface the error
    case unknownState        // state unknown — suppress the alert, log only
}

/// Pure decision function: a failed stop is a real error **only** when a
/// post-failure refresh confirms the VM still runs. A stopped/absent VM
/// reconciles to success; a failed/stale refresh yields `.unknownState`
/// — the caller must not fire a false error on unknown state.
public enum StopReconciler {
    public static func reconcile(_ postStop: PostStopInventory) -> StopReconciliation {
        switch postStop {
        case .fresh(let entry):
            return entry?.running == true ? .runningConfirmed : .reconciledStopped
        case .stale:
            return .unknownState
        }
    }
}
