import Foundation
import os

/// Provenance-gated cleanup for a failed or cancelled create-from-IPSW (the
/// contract already established for import, replicated for the analogous
/// operation). Cleanup never deletes anything it cannot attribute to the
/// just-finished job: an entry is the create's artifact only when its
/// last-access timestamp falls inside the job's window
/// (`jobStartedAt...jobEndedAt`). tart holds the destination name for the
/// entire run (its own uniqueness enforcement), so anything accessed before
/// the job started pre-existed it, and anything accessed after the job ended
/// was created by someone else — both are preserved and surfaced. Decisions
/// are made over a freshly listed inventory, never the app's cached poll state.
public enum PartialCreateCleanup: Sendable {
    public enum Decision: Equatable, Sendable {
        case nothingToDo        // name absent from the fresh list
        case conflictPreserved  // entry outside the job window — never delete
        case artifact           // entry inside the job window — safe to delete
    }

    public enum Result: Equatable, Sendable {
        case notFound
        case preserved
        case deleted
        case listFailed
        case deleteFailed
    }

    private static let log = Logger.createCleanup

    /// Pure decision over a freshly listed inventory.
    public static func decide(entries: [VMEntry], name: String,
                              jobStartedAt: Date, jobEndedAt: Date) -> Decision {
        guard let entry = entries.first(where: { $0.name == name }) else {
            return .nothingToDo
        }
        guard let accessed = entry.accessed,
              accessed >= jobStartedAt, accessed <= jobEndedAt else {
            return .conflictPreserved
        }
        return .artifact
    }

    /// Runs the cleanup with injected list/delete operations (hermetic tests)
    /// and never throws: every anomaly is logged and surfaced via `onFailure`
    /// (wired to the app's standard error sheet). No silent data loss and no
    /// silent phantom entries.
    @discardableResult
    public static func perform(
        name: String,
        jobStartedAt: Date,
        jobEndedAt: Date,
        list: @escaping @Sendable () throws -> [VMEntry],
        delete: @escaping @Sendable (String) throws -> Void,
        onFailure: @escaping @Sendable (TartClientError) -> Void
    ) -> Result {
        let entries: [VMEntry]
        do {
            entries = try list()
        } catch {
            let failure = normalized(error, command: "list")
            let message = "create cleanup: re-list failed for \(name) "
                + "(\(String(describing: failure))); a half-materialized entry may remain"
            log.error("\(message, privacy: .public)")
            onFailure(failure)
            return .listFailed
        }

        switch decide(entries: entries, name: name,
                      jobStartedAt: jobStartedAt, jobEndedAt: jobEndedAt) {
        case .nothingToDo:
            log.notice("create cleanup: no '\(name, privacy: .public)' entry — tart's create was atomic; nothing to remove")
            return .notFound
        case .conflictPreserved:
            log.error("create cleanup: '\(name, privacy: .public)' exists outside the job window — NOT deleting (pre-existing or externally created)")
            onFailure(TartClientError.commandFailed(
                command: "create-cleanup", exitCode: -1, stdout: "",
                stderr: "A VM named '\(name)' appeared outside the create's window; "
                        + "it was left untouched."))
            return .preserved
        case .artifact:
            do {
                try delete(name)
                log.notice("create cleanup: removed half-materialized '\(name, privacy: .public)'")
                return .deleted
            } catch {
                let failure = normalized(error, command: "delete")
                let message = "create cleanup: delete failed for \(name) "
                    + "(\(String(describing: failure)))"
                log.error("\(message, privacy: .public)")
                onFailure(failure)
                return .deleteFailed
            }
        }
    }

    private static func normalized(_ error: Error, command: String) -> TartClientError {
        (error as? TartClientError)
            ?? TartClientError.commandFailed(command: command, exitCode: -1,
                                             stdout: "", stderr: "\(error)")
    }
}
