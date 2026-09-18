import Foundation

/// What the inventory tells us about a VM after the post-failure refresh.
public enum PostSuspendInventory: Equatable, Sendable {
    /// A fetch completed after the failed suspend attempt. The associated
    /// entry is the VM's current listing, or nil when it vanished from the
    /// list.
    case fresh(VMEntry?)
    /// The refresh failed or never ran (skipped by the in-flight guard):
    /// nothing trustworthy to conclude from.
    case stale
}

/// The decision for a failed suspend command (the stop-mirroring rule).
public enum SuspendReconciliation: Equatable, Sendable {
    case reconciledNotRunning // VM gone/suspended/stopped — success, no error
    case runningConfirmed     // VM confirmed still running — surface the error
    case unknownState         // state unknown — suppress the alert, log only
}

/// Pure decision function: a failed suspend is a real error **only** when a
/// post-failure refresh confirms the VM still runs. A suspended/stopped/
/// absent VM reconciles to success; a failed/stale refresh yields
/// `.unknownState` — the caller must not fire a false error on unknown
/// state (mirrors the stop flow's rule).
public enum SuspendReconciler {
    public static func reconcile(_ postSuspend: PostSuspendInventory) -> SuspendReconciliation {
        switch postSuspend {
        case .fresh(let entry):
            return entry?.running == true ? .runningConfirmed : .reconciledNotRunning
        case .stale:
            return .unknownState
        }
    }
}
