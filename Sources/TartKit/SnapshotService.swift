import Foundation
import os

/// The Snapshot Service (PRD Module Design): export-based snapshot semantics.
/// Lives in TartKit so the folder defaulting and the create pipeline carry
/// unit tests and the App UI stays thin plumbing (finding 4).
public enum SnapshotService {
    /// The resolved snapshots folder: the configured setting when set,
    /// otherwise a `Snapshots` sibling of the VM storage folder (same volume).
    /// Returns nil when neither is available — the app is mid-onboarding and
    /// no snapshots surface is reachable. There is deliberately NO temp-
    /// directory fallback: full VM disk images must never be written to a
    /// volatile, OS-purged temporary directory (finding 8).
    public static func resolveDirectory(storagePath: String?,
                                        configuredFolder: String?) -> String? {
        if let configuredFolder {
            return configuredFolder
        }
        guard let storagePath else { return nil }
        return ((storagePath as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent("Snapshots")
    }
}

/// The snapshot-create job body as a hermetic TartKit unit (injected
/// operations), satisfying the issue's automated-verification requirements —
/// correct export to the correct path/filename, stopped-only enforcement, and
/// failure paths leaving the catalog consistent — without a real tart or an
/// app instance (finding 4). Run by `AppModel.createSnapshot` inside a
/// JobManager job; nonisolated and `Sendable`.
public struct SnapshotCreateJob: Sendable {
    public struct Ops: Sendable {
        public var ensureDirectory: @Sendable (String) throws -> Void
        public var list: @Sendable () throws -> [VMEntry]
        public var export: @Sendable (String, String,
            @escaping @Sendable (String) -> Void,
            @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.ExportOutcome

        public init(
            ensureDirectory: @escaping @Sendable (String) throws -> Void,
            list: @escaping @Sendable () throws -> [VMEntry],
            export: @escaping @Sendable (String, String,
                @escaping @Sendable (String) -> Void,
                @escaping @Sendable (@escaping @Sendable () -> Void) -> Void) throws -> TartClient.ExportOutcome
        ) {
            self.ensureDirectory = ensureDirectory
            self.list = list
            self.export = export
        }
    }

    public let vmName: String
    public let label: String?
    public let archivePath: String
    public let createdAt: Date
    public let directory: String
    public let store: SnapshotStore
    public let ops: Ops

    private static let log = Logger.snapshot

    public init(vmName: String, label: String?, archivePath: String,
                createdAt: Date, directory: String, store: SnapshotStore, ops: Ops) {
        self.vmName = vmName
        self.label = label
        self.archivePath = archivePath
        self.createdAt = createdAt
        self.directory = directory
        self.store = store
        self.ops = ops
    }

    /// Runs the export inside a JobManager job. Indeterminate by design: the
    /// job reports `exporting…` exactly once and never parses output
    /// (finding 10). Failure/cancel paths write no sidecar, so the per-VM
    /// catalog stays consistent; a leftover partial archive degrades to an
    /// unowned foreign entry (finding 7).
    public func run(context: JobContext) throws {
        let startLine = "snapshot: starting export of \(vmName) → \(archivePath)"
        Self.log.notice("\(startLine, privacy: .public)")
        context.report(PullProgress(fraction: nil, note: "exporting…"))
        let began = Date()

        do {
            try ops.ensureDirectory(directory)
        } catch {
            let message = "Could not create the snapshots folder at \(directory): \(error)"
            Self.log.error("snapshot: \(message, privacy: .public)")
            throw TartClientError.commandFailed(command: "export", exitCode: -1,
                                                stdout: "", stderr: message)
        }

        // Stopped-only enforcement, re-verified against a FRESH list right
        // before the export (the UI gate can be seconds stale).
        do {
            let entries = try ops.list()
            if let entry = entries.first(where: { $0.name == vmName }), entry.running {
                let refusalLine = "snapshot: \(vmName) is running — refusing export (stopped-only)"
                Self.log.error("\(refusalLine, privacy: .public)")
                throw TartClientError.commandFailed(
                    command: "export", exitCode: -1, stdout: "",
                    stderr: "VM '\(vmName)' is running. Stop it before taking a snapshot.")
            }
        } catch let failure as TartClientError {
            let verifyLine = "snapshot: could not verify the state of \(vmName): \(failure)"
            Self.log.error("\(verifyLine, privacy: .public)")
            throw failure
        }

        let outcome: TartClient.ExportOutcome
        do {
            outcome = try ops.export(vmName, archivePath, { _ in }, { action in
                context.registerCancel(action)
            })
        } catch {
            let failure = error as? TartClientError
                ?? TartClientError.commandFailed(command: "export", exitCode: -1,
                                                 stdout: "", stderr: "\(error)")
            let duration = Date().timeIntervalSince(began)
            let line = "snapshot: export of \(vmName) failed after "
                + "\(String(format: "%.1f", duration))s (\(failure)) — no sidecar written"
            Self.log.error("\(line, privacy: .public)")
            throw failure
        }

        if outcome == .cancelled || context.isCancelled {
            let cancelLine = "snapshot: export of \(vmName) cancelled — archive at "
                + "\(archivePath) may be partial; no sidecar written (unowned entry if it remains)"
            Self.log.notice("\(cancelLine, privacy: .public)")
            return
        }

        do {
            try store.writeMetadata(archivePath: archivePath, vmName: vmName,
                                     label: label, createdAt: createdAt)
            Self.log.notice("snapshot: sidecar written for \(archivePath, privacy: .public)")
        } catch {
            let message = "The export completed but its sidecar could not be written: \(error)"
            Self.log.error("snapshot: \(message, privacy: .public)")
            throw TartClientError.commandFailed(command: "export", exitCode: -1,
                                                stdout: "", stderr: message)
        }
    }
}
