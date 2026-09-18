import Foundation
import os

/// Guarded local-clone orchestration: validates source and destination
/// **before any subprocess spawns** (the issue's mandated automated check),
/// then starts the shared `JobManager.startClone` body. Lives in TartKit so
/// the guards and the refusal semantics carry unit tests; `AppModel` stays
/// thin plumbing (findings 2 and 3).
@MainActor
public final class CloneCoordinator {
    /// Why a clone must not start.
    public enum Refusal: Equatable, Sendable {
        case source(CloneGuard.SourceIssue)
        case name(CloneGuard.NameIssue)
    }

    /// The result of one start attempt.
    public enum StartOutcome: Equatable, Sendable {
        case started(jobID: UUID)
        case refused(reason: Refusal)
    }

    public init() {}

    /// Pure pre-flight validation (no I/O): the UI calls this for inline
    /// feedback; `start` applies it again immediately before the job spawn.
    public func validate(source: VMEntry, newName: String,
                         taken: Set<String>) -> Refusal? {
        if let issue = CloneGuard.validateSource(source) {
            return .source(issue)
        }
        if let issue = CloneGuard.validateName(newName, taken: taken) {
            return .name(issue)
        }
        return nil
    }

    /// Starts the clone job after validation. The guards run strictly before
    /// `JobManager.startClone`, so a refused clone never spawns tart
    /// (asserted with a marker-file stub in `CloneCoordinatorTests`).
    public func start(source: VMEntry, newName: String, taken: Set<String>,
                      using client: TartClient,
                      jobManager: JobManager) -> StartOutcome {
        if let refusal = validate(source: source, newName: newName, taken: taken) {
            Logger.clone.info(
                "local clone of \(source.name, privacy: .public) refused: \(String(describing: refusal), privacy: .public)")
            return .refused(reason: refusal)
        }
        guard let job = jobManager.startClone(source: source.name, to: newName,
                                              using: client) else {
            // The manager holds a duplicate target in flight — parity with the
            // dialog's taken-name feedback, never a silent no-op.
            let refusal = Refusal.name(.taken)
            Logger.clone.info(
                "local clone of \(source.name, privacy: .public) refused: \(String(describing: refusal), privacy: .public)")
            return .refused(reason: refusal)
        }
        return .started(jobID: job.id)
    }
}
