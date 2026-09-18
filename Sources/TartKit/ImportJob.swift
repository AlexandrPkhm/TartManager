import Foundation
import os

/// The import job body as a hermetic TartKit unit (injected operations), so
/// the issue's automated-verification requirements — uniqueness
/// pre-validation, and failure/cancel paths leaving consistent list state —
/// are testable without a real tart or an app instance. Run by
/// `AppModel.startImport` inside a JobManager job; nonisolated and `Sendable`,
/// so the detached job body never touches a main-actor-isolated member.
public struct ImportJob: Sendable {
    public struct Ops: Sendable {
        public var list: @Sendable () throws -> [VMEntry]
        public var importArchive: @Sendable (String, String,
            @escaping @Sendable (String) -> Void,
            @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.ImportOutcome
        public var delete: @Sendable (String) throws -> Void

        public init(
            list: @escaping @Sendable () throws -> [VMEntry],
            importArchive: @escaping @Sendable (String, String,
                @escaping @Sendable (String) -> Void,
                @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.ImportOutcome,
            delete: @escaping @Sendable (String) throws -> Void
        ) {
            self.list = list
            self.importArchive = importArchive
            self.delete = delete
        }
    }

    public let name: String
    public let path: String
    public let startedAt: Date
    public let ops: Ops
    /// Cleanup anomalies (preserved conflicts, list/delete failures) are
    /// surfaced here — normally wired to the app's standard error sheet.
    public let onCleanupAnomaly: @Sendable (TartClientError) -> Void

    private static let log = Logger.importJob

    public init(name: String, path: String, startedAt: Date, ops: Ops,
                onCleanupAnomaly: @escaping @Sendable (TartClientError) -> Void) {
        self.name = name
        self.path = path
        self.startedAt = startedAt
        self.ops = ops
        self.onCleanupAnomaly = onCleanupAnomaly
    }

    /// Runs the import inside a JobManager job. Throws normalized import
    /// failures (client-owned); cleanup is best-effort and never throws.
    /// No progress parsing: tart import prints no parseable percentages, so
    /// the job reports the indeterminate form exactly once.
    public func run(context: JobContext) throws {
        // Uniqueness pre-validation against a FRESH list (not the cached
        // inventory): the name is re-checked immediately before any transfer.
        let entries = try ops.list()
        guard !entries.contains(where: { $0.name == name }) else {
            Self.log.error("import pre-flight: '\(name, privacy: .public)' already exists at launch; refusing before any transfer")
            throw TartClientError.commandFailed(
                command: "import", exitCode: -1, stdout: "",
                stderr: "a VM named '\(name)' already exists")
        }

        context.report(PullProgress(fraction: nil, note: "importing…"))
        Self.log.notice("import: starting \(path, privacy: .public) → \(name, privacy: .public)")
        let began = Date()
        let outcome: TartClient.ImportOutcome
        do {
            outcome = try ops.importArchive(path, name, { _ in }, { action in
                context.registerCancel(action)
            })
        } catch {
            let failure = error as? TartClientError
                ?? TartClientError.commandFailed(command: "import", exitCode: -1,
                                                 stdout: "", stderr: "\(error)")
            let duration = Date().timeIntervalSince(began)
            let message = "import: failed after \(String(format: "%.1f", duration))s "
                + "(\(String(describing: failure)))"
            Self.log.error("\(message, privacy: .public)")
            if Self.isNameCollision(failure) {
                // Someone else won the name in the launch race: the import
                // created nothing — cleanup must NOT delete that VM.
                Self.log.notice("import: name-collision failure — skipping cleanup")
                throw failure
            }
            cleanup(jobEndedAt: Date())
            throw failure
        }

        if outcome == .cancelled || context.isCancelled {
            Self.log.notice("import: cancelled — running cleanup")
            cleanup(jobEndedAt: Date())
            return
        }
        Self.log.notice("import: completed — \(name, privacy: .public) is ready")
    }

    private func cleanup(jobEndedAt: Date) {
        PartialImportCleanup.perform(
            name: name,
            jobStartedAt: startedAt,
            jobEndedAt: jobEndedAt,
            list: ops.list,
            delete: ops.delete,
            onFailure: onCleanupAnomaly)
    }

    /// tart's collision signature in a failed import's output. Only failures
    /// matching it skip cleanup: any other failure means tart held the name
    /// and may have left a half-materialized entry.
    static func isNameCollision(_ failure: TartClientError) -> Bool {
        guard case .commandFailed(_, _, _, let stderr) = failure else { return false }
        return stderr.range(of: "already exists", options: .caseInsensitive) != nil
    }
}
