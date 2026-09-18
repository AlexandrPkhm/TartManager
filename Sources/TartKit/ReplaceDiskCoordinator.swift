import Foundation
import os

/// Guarded replace-disk orchestration: validates the confirmation gate, the
/// VM state, and locality **before any subprocess spawns** (the issue's
/// mandated automated checks), then starts the job whose body streams
/// `TartClient.replaceDisk`. Lives in TartKit so the guards, the refusal
/// semantics, and the audit logging carry unit tests; `AppModel` stays thin
/// plumbing (findings 2, 4, 5).
@MainActor
public final class ReplaceDiskCoordinator {
    public enum StartOutcome: Equatable, Sendable {
        case started(jobID: UUID)
        case refused(reason: ReplaceDiskGuard.Refusal)
    }

    public init() {}

    /// Starts the replace job after validation. The guards run strictly
    /// before `JobManager.start`, so a refused replace never spawns tart
    /// (asserted with marker-file stubs in `ReplaceDiskCoordinatorTests`).
    /// A duplicate-target refusal from the manager is surfaced as
    /// `.inFlight`, never silently.
    public func start(vm: VMEntry, typedName: String, path: String,
                      using client: TartClient,
                      jobManager: JobManager) -> StartOutcome {
        if let refusal = ReplaceDiskGuard.refusal(vm: vm, typedName: typedName, path: path) {
            logRefusal(for: vm.name, refusal)
            return .refused(reason: refusal)
        }
        let name = vm.name
        let kind = JobInfo.Kind.replaceDisk(name: name, path: path)
        let result = jobManager.start(kind: kind) { context in
            context.report(PullProgress(fraction: nil, note: "replacing disk…"))
            let startLine = "replace disk: copying into \(name) from \(path)"
            Logger.replaceDisk.info("\(startLine, privacy: .public)")
            do {
                try client.replaceDisk(name: name, withPath: path)
                let successLine = "replace disk: \(name) replaced from \(path)"
                Logger.replaceDisk.info("\(successLine, privacy: .public)")
            } catch {
                let failureLine = "replace disk failed for \(name): \(String(describing: error))"
                Logger.replaceDisk.error("\(failureLine, privacy: .public)")
                throw error
            }
        }
        switch result {
        case .started(let job):
            return .started(jobID: job.id)
        case .duplicateTarget:
            logRefusal(for: name, .inFlight)
            return .refused(reason: .inFlight)
        }
    }

    private func logRefusal(for name: String, _ refusal: ReplaceDiskGuard.Refusal) {
        let line = "replace disk refused for \(name): \(String(describing: refusal))"
        Logger.replaceDisk.info("\(line, privacy: .public)")
    }
}
