import Foundation
import os

/// The create-from-IPSW job body as a hermetic TartKit unit (injected
/// operations), so the automated-verification requirements — uniqueness
/// pre-validation and phantom-free failure/cancel paths — are testable
/// without a real tart or an app instance. Run by the app model inside a
/// JobManager job; nonisolated and `Sendable`, so the detached job body
/// never touches a main-actor-isolated member.
public struct CreateFromIPSWJob: Sendable {
    public struct Ops: Sendable {
        public var list: @Sendable () throws -> [VMEntry]
        public var createFromIPSW: @Sendable (String, String, Int,
            @escaping @Sendable (String) -> Void,
            @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.CreateOutcome
        public var delete: @Sendable (String) throws -> Void

        public init(
            list: @escaping @Sendable () throws -> [VMEntry],
            createFromIPSW: @escaping @Sendable (String, String, Int,
                @escaping @Sendable (String) -> Void,
                @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.CreateOutcome,
            delete: @escaping @Sendable (String) throws -> Void
        ) {
            self.list = list
            self.createFromIPSW = createFromIPSW
            self.delete = delete
        }
    }

    public let name: String
    public let ipsw: String
    public let diskSizeGB: Int
    public let startedAt: Date
    public let ops: Ops
    /// Cleanup anomalies (preserved conflicts, list/delete failures) are
    /// surfaced here — normally wired to the app's standard error sheet.
    public let onCleanupAnomaly: @Sendable (TartClientError) -> Void

    private static let log = Logger.createJob

    public init(name: String, ipsw: String, diskSizeGB: Int, startedAt: Date,
                ops: Ops, onCleanupAnomaly: @escaping @Sendable (TartClientError) -> Void) {
        self.name = name
        self.ipsw = ipsw
        self.diskSizeGB = diskSizeGB
        self.startedAt = startedAt
        self.ops = ops
        self.onCleanupAnomaly = onCleanupAnomaly
    }

    /// Runs the create inside a JobManager job. Throws normalized create
    /// failures (client-owned); cleanup is best-effort and never throws.
    /// No progress parsing: restore output has no parseable percentages, so
    /// the job reports the indeterminate form exactly once and the client's
    /// accumulator is bounded (TextAccumulator, 64 KiB cap).
    public func run(context: JobContext) throws {
        // Uniqueness pre-validation against a FRESH list (not the cached
        // inventory): the name is re-checked immediately before any transfer.
        let entries = try ops.list()
        guard !entries.contains(where: { $0.name == name }) else {
            Self.log.error("create-from-IPSW pre-flight: '\(name, privacy: .public)' already exists at launch; refusing before any transfer")
            throw TartClientError.commandFailed(
                command: "create", exitCode: -1, stdout: "",
                stderr: "a VM named '\(name)' already exists")
        }

        context.report(PullProgress(fraction: nil, note: "installing…"))
        Self.log.notice("create-from-IPSW: starting \(ipsw, privacy: .public) → \(name, privacy: .public)")
        let began = Date()
        let outcome: TartClient.CreateOutcome
        do {
            // Raw chunks are for the client's capture/logging only; the job
            // never parses them.
            outcome = try ops.createFromIPSW(name, ipsw, diskSizeGB, { _ in }, { action in
                context.registerCancel(action)
            })
        } catch {
            let failure = error as? TartClientError
                ?? TartClientError.commandFailed(command: "create", exitCode: -1,
                                                 stdout: "", stderr: "\(error)")
            let duration = Date().timeIntervalSince(began)
            let failureLine = "create-from-IPSW: failed after \(String(format: "%.1f", duration))s "
                + "(\(String(describing: failure)))"
            Self.log.error("\(failureLine, privacy: .public)")
            if Self.isNameCollision(failure) {
                // Someone else won the name in the launch race: the create
                // produced nothing — cleanup must NOT delete that VM.
                Self.log.notice("create-from-IPSW: name-collision failure — skipping cleanup")
                throw failure
            }
            cleanup(jobEndedAt: Date())
            throw failure
        }

        if outcome == .cancelled || context.isCancelled {
            Self.log.notice("create-from-IPSW: cancelled — running cleanup")
            cleanup(jobEndedAt: Date())
            return
        }
        Self.log.notice("create-from-IPSW: completed — \(name, privacy: .public) is ready")
    }

    private func cleanup(jobEndedAt: Date) {
        PartialCreateCleanup.perform(
            name: name,
            jobStartedAt: startedAt,
            jobEndedAt: jobEndedAt,
            list: ops.list,
            delete: ops.delete,
            onFailure: onCleanupAnomaly)
    }

    /// tart's collision signature in a failed create's output. Only failures
    /// matching it skip cleanup: any other failure means tart held the name
    /// and may have left a half-materialized entry.
    static func isNameCollision(_ failure: TartClientError) -> Bool {
        guard case .commandFailed(_, _, _, let stderr) = failure else { return false }
        return stderr.range(of: "already exists", options: .caseInsensitive) != nil
    }
}
