import Foundation
import Combine
import os

/// Orchestrates VM stops: pre-checks, the single-flight `stopping`
/// reservation, the off-main-actor command, failure normalization, and the
/// race-tolerance reconciliation. Lives in TartKit so the whole
/// orchestration carries unit tests; `AppModel` stays thin plumbing.
@MainActor
public final class StopCoordinator: ObservableObject {
    /// The result of one stop attempt, ready for the App UI to render.
    public enum Outcome: Equatable {
        /// The command succeeded.
        case stopped
        /// The command failed but the post-failure refresh shows the VM
        /// gone/stopped — success, no alert.
        case reconciled(name: String)
        /// The command failed and the VM is confirmed still running —
        /// a real error to surface. `message` is the legacy presentation
        /// text; `cause` is the raw client failure for the standardized
        /// error report.
        case stillRunning(name: String, message: String, cause: TartClientError)
        /// The command failed but the post-stop state is unknown (the
        /// refresh itself failed or was skipped) — suppress the alert.
        case unknown(name: String)
        /// A stop is already in flight for this VM (double-click guard).
        case alreadyStopping(name: String)
        /// Pre-check skip: not a running local VM.
        case notStoppable(name: String)
    }

    /// VMs with a stop in flight — the row spinners and the double-click
    /// guard. Published so `VMRowView`/`VMListView` observe it directly.
    @Published public private(set) var stopping: Set<String> = []

    public init() {}

    /// Stops `vm` gracefully (`force` = immediate). The name is reserved
    /// synchronously on the main actor before the first `await`, so a fast
    /// double-stop can never pile up two commands. On failure the inventory
    /// is refreshed once and `StopReconciler` decides whether this is a
    /// real error, a reconciled race, or an unknown state.
    public func stop(vm: VMEntry, force: Bool = false,
                     using client: TartClient,
                     inventory: InventoryService) async -> Outcome {
        guard vm.isLocal, vm.running else { return .notStoppable(name: vm.name) }
        let name = vm.name
        guard !stopping.contains(name) else { return .alreadyStopping(name: name) }
        stopping.insert(name)
        defer { stopping.remove(name) }

        let timeout: Int? = force ? 0 : nil
        Logger.stop.info("stop started for '\(name, privacy: .public)' (\(force ? "force" : "graceful"))")

        let failure: String?
        var failureCause: TartClientError?
        do {
            try await client.stop(name: name, timeout: timeout)
            failure = nil
        } catch {
            failureCause = (error as? TartClientError)
                ?? TartClientError.commandFailed(command: "stop", exitCode: -1, stdout: "", stderr: "\(error)")
            failure = Self.failureText(error)
        }

        guard let failure, let failureCause else {
            Logger.stop.info("stop of '\(name, privacy: .public)' completed (\(force ? "force" : "graceful"))")
            return .stopped
        }

        // Race tolerance: refresh once and decide (the issue's defining rule).
        Logger.stop.error("stop of '\(name, privacy: .public)' failed: \(failure, privacy: .public); refreshing to reconcile")
        let before = inventory.lastFetchedAt
        await inventory.refresh()
        let after = inventory.lastFetchedAt
        // `refresh()` is skipped while a poll fetch is in flight and failures
        // never update `lastFetchedAt` — either way the snapshot is stale
        // and must not be trusted as "not running".
        let postStop: PostStopInventory = (after != nil && after != before)
            ? .fresh(inventory.inventory?.localVMs.first { $0.name == name })
            : .stale

        switch StopReconciler.reconcile(postStop) {
        case .runningConfirmed:
            let message = "Couldn't stop \(name):\n\(failure)"
            Logger.stop.error("stop of '\(name, privacy: .public)' confirmed failed; error: \(failure, privacy: .public)")
            return .stillRunning(name: name, message: message, cause: failureCause)
        case .reconciledStopped:
            Logger.stop.info("'\(name, privacy: .public)' is no longer running — failed stop reconciled as success")
            return .reconciled(name: name)
        case .unknownState:
            Logger.stop.warning("post-stop state of '\(name, privacy: .public)' is unknown (refresh failed or was skipped) — suppressing the alert; failure: \(failure, privacy: .public)")
            return .unknown(name: name)
        }
    }

    /// Normalizes a stop error into user-facing text (asserted through the
    /// `.stillRunning` outcome in tests; `AppModel` never builds messages).
    static func failureText(_ error: Error) -> String {
        switch error {
        case let TartClientError.commandFailed(_, exitCode, _, stderr):
            return "tart exited with code \(exitCode): \(stderr)"
        default:
            return "\(error)"
        }
    }
}
