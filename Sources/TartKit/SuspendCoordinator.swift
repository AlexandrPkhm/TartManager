import Foundation
import Combine
import os

/// Orchestrates VM suspends: pre-checks, the single-flight `suspending`
/// reservation, the off-main-actor command, failure normalization, and the
/// race-tolerance reconciliation. Lives in TartKit so the whole
/// orchestration carries unit tests; `AppModel` stays thin plumbing.
/// Mirrors the stop flow's pattern (`suspending` set + refresh-then-confirm)
/// so a double-click can never pile up two commands and a stale-row Suspend
/// can never raise a misleading error.
@MainActor
public final class SuspendCoordinator: ObservableObject {
    /// The result of one suspend attempt, ready for the App UI to render.
    public enum Outcome: Equatable {
        /// The command succeeded; the VM is parked.
        case suspended
        /// The command failed but the post-failure refresh shows the VM
        /// no longer running (suspended anyway, stopped, or gone) —
        /// success, no alert.
        case reconciled(name: String)
        /// The command failed and the VM is confirmed still running —
        /// a real error to surface through the standard sheet.
        case stillRunning(name: String, error: TartOperationError)
        /// The command failed but the post-suspend state is unknown (the
        /// refresh itself failed or was skipped) — suppress the alert.
        case unknown(name: String)
        /// A suspend is already in flight for this VM (double-click guard).
        case alreadySuspending(name: String)
        /// Pre-check skip: not a running local VM.
        case notSuspendable(name: String)
    }

    /// VMs with a suspend in flight — the row spinners and the double-click
    /// guard. Published so `VMRowView` observes it directly.
    @Published public private(set) var suspending: Set<String> = []

    public init() {}

    /// Suspends `vm`. The name is reserved synchronously on the main actor
    /// before the first `await`, so a fast double-click can never pile up
    /// two commands. On failure the inventory is refreshed once and
    /// `SuspendReconciler` decides whether this is a real error, a
    /// reconciled race, or an unknown state.
    public func suspend(vm: VMEntry,
                        using client: TartClient,
                        inventory: InventoryService) async -> Outcome {
        guard vm.isLocal, vm.running else { return .notSuspendable(name: vm.name) }
        let name = vm.name
        guard !suspending.contains(name) else { return .alreadySuspending(name: name) }
        suspending.insert(name)
        defer { suspending.remove(name) }

        Logger.suspend.info("suspend started for '\(name, privacy: .public)'")

        let failure: TartOperationError?
        do {
            try await client.suspend(name: name)
            failure = nil
        } catch let error as TartClientError {
            failure = error.normalized
        } catch {
            failure = TartClientError.commandFailed(
                command: "suspend", exitCode: -1, stdout: "", stderr: "\(error)").normalized
        }

        guard let failure else {
            Logger.suspend.info("suspend of '\(name, privacy: .public)' completed")
            return .suspended
        }

        // Race tolerance (mirrors stop): refresh once and decide.
        Logger.suspend.error(
            "suspend of '\(name, privacy: .public)' failed: \(failure.message, privacy: .public); refreshing to reconcile")
        let before = inventory.lastFetchedAt
        await inventory.refresh()
        let after = inventory.lastFetchedAt
        // `refresh()` is skipped while a poll fetch is in flight and failures
        // never update `lastFetchedAt` (Issue 4, Task 6) — either way the
        // snapshot is stale and must not be trusted as "not running".
        let postSuspend: PostSuspendInventory = (after != nil && after != before)
            ? .fresh(inventory.inventory?.localVMs.first { $0.name == name })
            : .stale

        switch SuspendReconciler.reconcile(postSuspend) {
        case .runningConfirmed:
            Logger.suspend.error(
                "suspend of '\(name, privacy: .public)' confirmed failed; error: \(failure.message, privacy: .public)")
            return .stillRunning(name: name, error: failure)
        case .reconciledNotRunning:
            Logger.suspend.info(
                "'\(name, privacy: .public)' is no longer running — failed suspend reconciled as success")
            return .reconciled(name: name)
        case .unknownState:
            Logger.suspend.warning(
                "post-suspend state of '\(name, privacy: .public)' is unknown (refresh failed or was skipped) — suppressing the alert; failure: \(failure.message, privacy: .public)")
            return .unknown(name: name)
        }
    }
}
