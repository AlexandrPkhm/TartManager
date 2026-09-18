import Foundation
import os

/// The restore job body as a hermetic TartKit unit (injected operations), so
/// the automated-verification requirements — pipeline ordering, safety-net
/// behavior, pre-flight refusals, race tolerances, failure guidance with the
/// archive path, and bounded error capture — are testable without a real tart
/// or an app instance. Run by `AppModel.restore` inside a JobManager job;
/// nonisolated and `Sendable`.
public struct SnapshotRestoreJob: Sendable {
    public struct Ops: Sendable {
        public var stop: @Sendable (String) throws -> Void
        public var list: @Sendable () throws -> [VMEntry]
        public var export: @Sendable (String, String,
            @escaping @Sendable (String) -> Void,
            @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.ExportOutcome
        public var delete: @Sendable (String) throws -> Void
        public var importArchive: @Sendable (String, String,
            @escaping @Sendable (String) -> Void,
            @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.ImportOutcome
        /// True when the source archive exists and is readable.
        public var sourceStatus: @Sendable (String) -> Bool
        public var fileSize: @Sendable (String) -> Int64?
        public var freeBytes: @Sendable (String) -> Int64?

        public init(
            stop: @escaping @Sendable (String) throws -> Void,
            list: @escaping @Sendable () throws -> [VMEntry],
            export: @escaping @Sendable (String, String,
                @escaping @Sendable (String) -> Void,
                @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.ExportOutcome,
            delete: @escaping @Sendable (String) throws -> Void,
            importArchive: @escaping @Sendable (String, String,
                @escaping @Sendable (String) -> Void,
                @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.ImportOutcome,
            sourceStatus: @escaping @Sendable (String) -> Bool,
            fileSize: @escaping @Sendable (String) -> Int64?,
            freeBytes: @escaping @Sendable (String) -> Int64?
        ) {
            self.stop = stop
            self.list = list
            self.export = export
            self.delete = delete
            self.importArchive = importArchive
            self.sourceStatus = sourceStatus
            self.fileSize = fileSize
            self.freeBytes = freeBytes
        }
    }

    public let vmName: String
    public let archivePath: String
    public let safetyArchivePath: String?
    public let vmDiskUsageGB: Double
    public let storagePath: String
    public let store: SnapshotStore
    public let safetyCreatedAt: Date
    public let ops: Ops

    private static let log = Logger.restore

    public init(vmName: String, archivePath: String, safetyArchivePath: String?,
                vmDiskUsageGB: Double, storagePath: String, store: SnapshotStore,
                safetyCreatedAt: Date, ops: Ops) {
        self.vmName = vmName
        self.archivePath = archivePath
        self.safetyArchivePath = safetyArchivePath
        self.vmDiskUsageGB = vmDiskUsageGB
        self.storagePath = storagePath
        self.store = store
        self.safetyCreatedAt = safetyCreatedAt
        self.ops = ops
    }

    /// Captures raw subprocess details (and the unknown-stop-state marker)
    /// from whichever stage adapter failed, for the final failure message.
    private final class StageErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storedRaw = ""
        private var storedUnknown = false

        func set(raw: String, stopStateUnknown: Bool = false) {
            lock.lock()
            storedRaw = raw
            storedUnknown = storedUnknown || stopStateUnknown
            lock.unlock()
        }

        var raw: String {
            lock.lock()
            defer { lock.unlock() }
            return storedRaw
        }

        var stopStateUnknown: Bool {
            lock.lock()
            defer { lock.unlock() }
            return storedUnknown
        }
    }

    /// Runs the restore inside a JobManager job. Stage notes are reported
    /// FROM INSIDE the op adapters as the pipeline advances; pre-flight
    /// refusals happen before any op; failures throw
    /// `TartClientError.commandFailed(command: "restore", …)` whose stderr is
    /// stage guidance plus bounded raw details.
    public func run(context: JobContext) throws {
        let began = Date()
        let safetyDetail = safetyArchivePath.map { " (safety → \($0))" } ?? ""
        Self.log.notice("restore: starting \(vmName, privacy: .public) ← \(archivePath, privacy: .public)\(safetyDetail, privacy: .public)")
        context.report(PullProgress(fraction: nil, note: "preparing…"))

        // Pre-flight 1 — the source archive must exist and be readable
        // BEFORE anything is touched.
        guard ops.sourceStatus(archivePath) else {
            let message = "The snapshot archive at \(archivePath) is missing or "
                + "unreadable — the current VM was left untouched."
            Self.log.error("restore: \(message, privacy: .public)")
            throw Self.failure(message)
        }

        // Pre-flight 2 — composite disk-space verdict BEFORE any destructive
        // stage. Restore refuses on a tight verdict: unlike clone/import there
        // is no mid-flight retry after the delete.
        if let problem = spaceProblemMessage() {
            Self.log.error("restore: \(problem, privacy: .public)")
            throw Self.failure(problem)
        }

        let stageError = StageErrorBox()
        let outcome = SnapshotRestorePipeline.restore(
            vmName: vmName,
            archivePath: archivePath,
            safetyArchivePath: safetyArchivePath,
            operations: SnapshotRestorePipeline.Operations(
                stop: { name in
                    try self.stopStage(name, context: context, stageError: stageError)
                },
                export: { name, path in
                    try self.exportStage(name, to: path, context: context, stageError: stageError)
                },
                delete: { name in
                    try self.deleteStage(name, context: context, stageError: stageError)
                },
                importArchive: { path, name in
                    try self.importStage(path, name, context: context, stageError: stageError)
                }))

        switch outcome {
        case .success:
            let seconds = String(format: "%.1f", Date().timeIntervalSince(began))
            Self.log.notice("restore: completed — \(vmName, privacy: .public) is restored in \(seconds, privacy: .public)s")
            return
        case .failure(let stage, let guidance):
            let raw = stageError.raw
            let finalMessage: String
            if stage == .stop && stageError.stopStateUnknown {
                // Unknown post-stop state can never mean "stopped" — with a
                // delete ahead the only safe choice is to abort.
                finalMessage = "Could not confirm the VM's state before restoring — "
                    + "nothing was changed." + (raw.isEmpty ? "" : "\n" + raw)
            } else {
                finalMessage = guidance + (raw.isEmpty ? "" : "\n" + raw)
            }
            Self.log.error("restore: failed at stage \(String(describing: stage), privacy: .public) — \(finalMessage, privacy: .public)")
            throw Self.failure(finalMessage)
        }
    }

    // MARK: - Stage adapters (progress notes live here)

    private func stopStage(_ name: String, context: JobContext,
                           stageError: StageErrorBox) throws {
        context.report(PullProgress(fraction: nil, note: "stopping…"))
        Self.log.notice("restore: stopping \(name, privacy: .public)")
        do {
            try ops.stop(name)
        } catch {
            stageError.set(raw: Self.rawText(of: error))
            // Reuse the pure stop reconciliation on a fresh list.
            let postStop: PostStopInventory
            do {
                let entries = try ops.list()
                postStop = .fresh(entries.first { $0.name == name })
            } catch {
                postStop = .stale
            }
            switch StopReconciler.reconcile(postStop) {
            case .reconciledStopped:
                Self.log.notice("restore: \(name, privacy: .public) already stopped — reconciled race, continuing")
                return
            case .runningConfirmed:
                throw error
            case .unknownState:
                stageError.set(raw: Self.rawText(of: error), stopStateUnknown: true)
                throw error
            }
        }
    }

    private func exportStage(_ name: String, to path: String, context: JobContext,
                             stageError: StageErrorBox) throws {
        context.report(PullProgress(fraction: nil, note: "saving current state first…"))
        Self.log.notice("restore: safety export \(name, privacy: .public) → \(path, privacy: .public)")
        let accumulator = TextAccumulator() // bounded 64 KiB tail
        do {
            let outcome = try ops.export(name, path,
                                         { accumulator.append($0) },
                                         { context.registerCancel($0) })
            if outcome == .cancelled || context.isCancelled {
                throw TartClientError.commandFailed(
                    command: "restore", exitCode: 1, stdout: "",
                    stderr: "the safety export was interrupted before completion")
            }
        } catch {
            stageError.set(raw: Self.rawText(of: error, fallback: accumulator.value))
            throw error
        }
        // The safety snapshot must be a first-class catalog entry BEFORE the
        // delete runs.
        do {
            try store.writeMetadata(archivePath: path, vmName: vmName,
                                    label: "safety-before-restore", createdAt: safetyCreatedAt)
            Self.log.notice("restore: safety sidecar written for \(path, privacy: .public)")
        } catch {
            stageError.set(raw: "\(error)")
            throw error
        }
    }

    private func deleteStage(_ name: String, context: JobContext,
                             stageError: StageErrorBox) throws {
        context.report(PullProgress(fraction: nil, note: "removing current VM…"))
        Self.log.notice("restore: deleting \(name, privacy: .public)")
        do {
            try ops.delete(name)
        } catch {
            stageError.set(raw: Self.rawText(of: error))
            // Race tolerance — a delete that failed because the VM was
            // already gone externally is success.
            if let entries = try? ops.list(),
               !entries.contains(where: { $0.name == name }) {
                Self.log.notice("restore: \(name, privacy: .public) already absent — reconciled race, continuing")
                return
            }
            throw error
        }
    }

    private func importStage(_ path: String, _ name: String, context: JobContext,
                             stageError: StageErrorBox) throws {
        context.report(PullProgress(fraction: nil, note: "restoring…"))
        Self.log.notice("restore: importing \(path, privacy: .public) → \(name, privacy: .public)")
        let accumulator = TextAccumulator() // bounded 64 KiB tail
        do {
            let outcome = try ops.importArchive(path, name,
                                                { accumulator.append($0) },
                                                { context.registerCancel($0) })
            if outcome == .cancelled || context.isCancelled {
                throw TartClientError.commandFailed(
                    command: "restore", exitCode: 1, stdout: "",
                    stderr: "the import was interrupted before completion")
            }
        } catch {
            stageError.set(raw: Self.rawText(of: error, fallback: accumulator.value))
            throw error
        }
    }

    // MARK: - Pre-flight and failure construction

    /// The composite space verdict: import on the VM-storage volume, plus the
    /// safety export on the snapshots volume when enabled. Any tight verdict
    /// produces a refusal message; nil = proceed.
    private func spaceProblemMessage() -> String? {
        var problems: [String] = []
        if let size = ops.fileSize(archivePath), size > 0,
           let free = ops.freeBytes(storagePath),
           let verdict = DiskSpacePolicy.importVerdict(archiveFileSizeBytes: size, freeBytes: free),
           verdict.isTight {
            problems.append("the import needs roughly "
                + ByteCountFormatter.string(
                    fromByteCount: DiskSpacePolicy.importEstimate(archiveFileSizeBytes: size),
                    countStyle: .file)
                + " but only " + ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                + " is free on the VM storage volume")
        }
        if safetyArchivePath != nil, vmDiskUsageGB > 0,
           let free = ops.freeBytes(store.directory),
           let verdict = DiskSpacePolicy.exportVerdict(vmDiskUsageGB: vmDiskUsageGB, freeBytes: free),
           verdict.isTight {
            problems.append("the safety snapshot needs roughly "
                + ByteCountFormatter.string(
                    fromByteCount: DiskSpacePolicy.exportEstimate(vmDiskUsageGB: vmDiskUsageGB),
                    countStyle: .file)
                + " but only " + ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                + " is free on the snapshots volume")
        }
        guard !problems.isEmpty else { return nil }
        return "Not enough free disk space to restore “\(vmName)” safely — "
            + "the current VM was left untouched.\n" + problems.joined(separator: "\n")
    }

    /// Raw subprocess details for the failure message: tart's stderr when the
    /// error carries it, else the bounded accumulated output, else the error
    /// description.
    static func rawText(of error: Error, fallback: String = "") -> String {
        if let tart = error as? TartClientError,
           case .commandFailed(_, _, _, let stderr) = tart {
            return stderr
        }
        return fallback.isEmpty ? "\(error)" : fallback
    }

    static func failure(_ message: String) -> TartClientError {
        TartClientError.commandFailed(command: "restore", exitCode: 1,
                                      stdout: "", stderr: message)
    }
}
