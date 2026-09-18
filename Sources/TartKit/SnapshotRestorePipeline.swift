import Foundation

/// Ordered, atomic snapshot-restore execution over injected operations.
/// Fails at the first error with a stage-labeled outcome — never continues
/// after a failure, so every terminal state is explainable. The message of a
/// failure is `RestoreFailureGuidance` for that stage: the pipeline owns
/// order, never user-facing text.
public enum SnapshotRestorePipeline {
    public enum Stage: Equatable, Sendable {
        case stop
        case safetyExport
        case delete
        case importArchive
    }

    public struct Operations {
        public let stop: (_ name: String) throws -> Void
        public let export: (_ name: String, _ path: String) throws -> Void
        public let delete: (_ name: String) throws -> Void
        public let importArchive: (_ path: String, _ name: String) throws -> Void

        public init(stop: @escaping (_ name: String) throws -> Void,
                    export: @escaping (_ name: String, _ path: String) throws -> Void,
                    delete: @escaping (_ name: String) throws -> Void,
                    importArchive: @escaping (_ path: String, _ name: String) throws -> Void) {
            self.stop = stop
            self.export = export
            self.delete = delete
            self.importArchive = importArchive
        }
    }

    public enum Outcome: Equatable, Sendable {
        case success
        case failure(stage: Stage, message: String)
    }

    public static func restore(vmName: String,
                               archivePath: String,
                               safetyArchivePath: String?,
                               operations: Operations) -> Outcome {
        do {
            try operations.stop(vmName)
        } catch {
            return .failure(stage: .stop,
                            message: RestoreFailureGuidance.message(for: .stop,
                                                                    archivePath: archivePath))
        }
        if let safetyArchivePath {
            do {
                try operations.export(vmName, safetyArchivePath)
            } catch {
                return .failure(stage: .safetyExport,
                                message: RestoreFailureGuidance.message(for: .safetyExport,
                                                                        archivePath: archivePath))
            }
        }
        do {
            try operations.delete(vmName)
        } catch {
            return .failure(stage: .delete,
                            message: RestoreFailureGuidance.message(for: .delete,
                                                                    archivePath: archivePath))
        }
        do {
            try operations.importArchive(archivePath, vmName)
        } catch {
            return .failure(stage: .importArchive,
                            message: RestoreFailureGuidance.message(for: .importArchive,
                                                                    archivePath: archivePath))
        }
        return .success
    }
}

/// The stage→guidance failure messaging of the restore pipeline, as a pure
/// tested function. The defining case: a failed import after a successful
/// delete states the VM is absent, that its data is intact in the archive at
/// the EXACT path, and that it can be re-imported.
public enum RestoreFailureGuidance {
    public static func message(for stage: SnapshotRestorePipeline.Stage,
                               archivePath: String) -> String {
        switch stage {
        case .stop:
            return "Could not stop the VM before restoring — nothing was changed."
        case .safetyExport:
            return "Could not create the safety snapshot of the current state "
                + "— the VM was left untouched."
        case .delete:
            return "Could not remove the current VM — nothing was changed."
        case .importArchive:
            return "The current VM was removed, but its data is safe in the "
                + "archive at \(archivePath) — it can be re-imported via the "
                + "Import… button."
        }
    }
}
