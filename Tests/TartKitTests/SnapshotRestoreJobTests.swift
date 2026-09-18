import Testing
import Foundation
@testable import TartKit

@Suite struct SnapshotRestoreJobTests {
    static func entry(_ name: String, running: Bool) -> VMEntry {
        VMEntry(name: name, source: "local", running: running,
                state: running ? "running" : "stopped",
                diskSize: 64, diskUsage: 20, accessed: nil)
    }

    /// Thread-safe recorder for the injected ops.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var listQueue: [Result<[VMEntry], TartClientError>] = []
        var order: [String] = []
        var stopCalls: [String] = []
        var stopError: Error?
        var exports: [(name: String, path: String)] = []
        var exportError: Error?
        var exportOutcome: TartClient.ExportOutcome = .completed
        var exportChunks: ((@Sendable (String) -> Void) -> Void)?
        var deletes: [String] = []
        var deleteError: Error?
        var imports: [(path: String, name: String)] = []
        var importError: Error?
        var importOutcome: TartClient.ImportOutcome = .completed
        var importChunks: ((@Sendable (String) -> Void) -> Void)?
        var reportedProgress: [PullProgress] = []
        var sourceStatusResult = true
        var fileSizeResult: Int64? = 10 * 1_073_741_824
        var freeBytesResults: [String: Int64?] = [:]

        func enqueueList(_ call: Result<[VMEntry], TartClientError>) {
            lock.lock()
            listQueue.append(call)
            lock.unlock()
        }

        func popList() -> Result<[VMEntry], TartClientError> {
            lock.lock()
            defer { lock.unlock() }
            return listQueue.isEmpty ? .success([]) : listQueue.removeFirst()
        }
    }

    struct Boom: Error {}

    func makeStore() -> (store: SnapshotStore, directory: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return (SnapshotStore(directory: dir.path), dir.path)
    }

    func makeJob(recorder: Recorder, store: SnapshotStore,
                 safetyArchivePath: String?) -> SnapshotRestoreJob {
        SnapshotRestoreJob(
            vmName: "vm-a",
            archivePath: "/snap/archive.tvm",
            safetyArchivePath: safetyArchivePath,
            vmDiskUsageGB: 20,
            storagePath: "/Volumes/SSD/Tart",
            store: store,
            safetyCreatedAt: Date(timeIntervalSince1970: 1_000),
            ops: SnapshotRestoreJob.Ops(
                stop: { recorder.order.append("stop"); recorder.stopCalls.append($0)
                    if let error = recorder.stopError { throw error } },
                list: { try recorder.popList().get() },
                export: { name, path, onOutput, register in
                    recorder.order.append("export")
                    recorder.exports.append((name, path))
                    recorder.exportChunks?(onOutput)
                    if let error = recorder.exportError { throw error }
                    return recorder.exportOutcome
                },
                delete: { recorder.order.append("delete"); recorder.deletes.append($0)
                    if let error = recorder.deleteError { throw error } },
                importArchive: { path, name, onOutput, register in
                    recorder.order.append("import")
                    recorder.imports.append((path, name))
                    recorder.importChunks?(onOutput)
                    if let error = recorder.importError { throw error }
                    return recorder.importOutcome
                },
                sourceStatus: { _ in recorder.sourceStatusResult },
                fileSize: { _ in recorder.fileSizeResult },
                freeBytes: { recorder.freeBytesResults[$0] ?? 500 * 1_073_741_824 }
            ))
    }

    func stderr(of error: TartClientError) -> String {
        if case .commandFailed(_, _, _, let stderr) = error { return stderr }
        return ""
    }

    func runExpectingError(_ job: SnapshotRestoreJob) -> TartClientError {
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch let error as TartClientError {
            return error
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        return TartClientError.commandFailed(command: "restore", exitCode: -1,
                                             stdout: "", stderr: "unreachable")
    }

    /// Stage notes are reported FROM INSIDE the op adapters as the pipeline
    /// advances — the row never freezes on "preparing…".
    @Test func reportsStageNotesAsPipelineAdvances() throws {
        let (store, _) = makeStore()
        let safetyPath = store.proposeArchivePath(vmName: "vm-a", label: "safety-before-restore")
        FileManager.default.createFile(atPath: safetyPath, contents: Data(count: 64))
        let recorder = Recorder()
        let job = makeJob(recorder: recorder, store: store, safetyArchivePath: safetyPath)

        try job.run(context: JobContext(report: { recorder.reportedProgress.append($0) }))

        #expect(recorder.reportedProgress == [
            PullProgress(fraction: nil, note: "preparing…"),
            PullProgress(fraction: nil, note: "stopping…"),
            PullProgress(fraction: nil, note: "saving current state first…"),
            PullProgress(fraction: nil, note: "removing current VM…"),
            PullProgress(fraction: nil, note: "restoring…"),
        ])
        #expect(recorder.order == ["stop", "export", "delete", "import"])
    }

    /// The safety export's sidecar is written BEFORE the delete, so the
    /// safety snapshot appears in the per-VM list afterwards.
    @Test func safetyExportWritesSidecarBeforeDelete() throws {
        let (store, _) = makeStore()
        let safetyPath = store.proposeArchivePath(vmName: "vm-a", label: "safety-before-restore")
        FileManager.default.createFile(atPath: safetyPath, contents: Data(count: 64))
        let recorder = Recorder()
        let job = makeJob(recorder: recorder, store: store, safetyArchivePath: safetyPath)

        try job.run(context: JobContext(report: { _ in }))

        #expect(recorder.order == ["stop", "export", "delete", "import"])
        let snapshots = try store.snapshots(forVM: "vm-a")
        #expect(snapshots.count == 1)
        #expect(snapshots[0].archivePath == safetyPath)
        #expect(snapshots[0].label == "safety-before-restore")
    }

    /// A missing/unreadable archive refuses BEFORE any op runs.
    @Test func preflightRefusesMissingArchiveBeforeAnyOp() {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.sourceStatusResult = false
        let job = makeJob(recorder: recorder, store: store,
                          safetyArchivePath: store.directory + "/safety.tvm")

        let error = runExpectingError(job)
        #expect(stderr(of: error).contains("missing or unreadable"))
        #expect(stderr(of: error).contains("/snap/archive.tvm"))
        #expect(stderr(of: error).contains("left untouched"))
        #expect(recorder.order.isEmpty) // nothing ran
    }

    /// A tight IMPORT-space verdict refuses before any op runs.
    @Test func preflightRefusesTightImportSpaceBeforeAnyOp() {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.fileSizeResult = 100 * 1_073_741_824
        recorder.freeBytesResults["/Volumes/SSD/Tart"] = 1_073_741_824
        let job = makeJob(recorder: recorder, store: store, safetyArchivePath: nil)

        let error = runExpectingError(job)
        #expect(stderr(of: error).contains("free disk space"))
        #expect(stderr(of: error).contains("left untouched"))
        #expect(recorder.order.isEmpty) // nothing ran
    }

    /// A tight SAFETY-export-space verdict refuses before any op.
    @Test func preflightRefusesTightSafetySpaceBeforeAnyOp() {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.freeBytesResults[store.directory] = 1_073_741_824
        let job = makeJob(recorder: recorder, store: store,
                          safetyArchivePath: store.directory + "/safety.tvm")

        let error = runExpectingError(job)
        #expect(stderr(of: error).contains("safety snapshot"))
        #expect(stderr(of: error).contains("left untouched"))
        #expect(recorder.order.isEmpty) // nothing ran
    }

    /// Ample space causes no interruption — no false refusals.
    @Test func ampleSpaceProceedsToRestore() throws {
        let (store, _) = makeStore()
        let recorder = Recorder()
        let job = makeJob(recorder: recorder, store: store,
                          safetyArchivePath: store.directory + "/safety.tvm")

        try job.run(context: JobContext(report: { _ in }))
        #expect(recorder.order == ["stop", "export", "delete", "import"])
    }

    /// A failed stop reconciles through the StopReconciler — a fresh list
    /// showing the VM gone means success, the pipeline continues.
    @Test func stopRaceReconcilesWhenFreshListShowsAbsent() throws {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.stopError = Boom()
        recorder.enqueueList(.success([]))
        let job = makeJob(recorder: recorder, store: store, safetyArchivePath: nil)

        try job.run(context: JobContext(report: { _ in }))
        #expect(recorder.order == ["stop", "delete", "import"])
        #expect(recorder.deletes == ["vm-a"])
        #expect(recorder.imports.count == 1)
    }

    /// A failed stop with the VM confirmed STILL RUNNING is a real stop-stage
    /// failure — nothing after it runs.
    @Test func stopFailureStillRunningAbortsBeforeDelete() {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.stopError = Boom()
        recorder.enqueueList(.success([Self.entry("vm-a", running: true)]))
        let job = makeJob(recorder: recorder, store: store, safetyArchivePath: nil)

        let error = runExpectingError(job)
        #expect(stderr(of: error).contains("Could not stop the VM before restoring"))
        #expect(recorder.order == ["stop"]) // delete/import never ran
    }

    /// Unknown post-stop state aborts with its OWN message — it is never
    /// treated as "stopped" (a delete follows).
    @Test func stopFailureUnknownStateAbortsWithConfirmedMessage() {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.stopError = Boom()
        recorder.enqueueList(.failure(TartClientError.commandFailed(
            command: "list", exitCode: 1, stdout: "", stderr: "storage down")))
        let job = makeJob(recorder: recorder, store: store, safetyArchivePath: nil)

        let error = runExpectingError(job)
        #expect(stderr(of: error).contains("Could not confirm the VM's state"))
        #expect(recorder.order == ["stop"]) // delete/import never ran
    }

    /// A failed delete of an ALREADY-ABSENT VM is success.
    @Test func deleteRaceTreatsAlreadyAbsentAsSuccess() throws {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.deleteError = Boom()
        recorder.enqueueList(.success([]))
        let job = makeJob(recorder: recorder, store: store, safetyArchivePath: nil)

        try job.run(context: JobContext(report: { _ in }))
        #expect(recorder.order == ["stop", "delete", "import"])
        #expect(recorder.imports.count == 1)
    }

    /// A failed delete with the VM still present is a real delete-stage
    /// failure — the import never runs.
    @Test func deleteFailureWhenVMStillPresentAborts() {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.deleteError = Boom()
        recorder.enqueueList(.success([Self.entry("vm-a", running: false)]))
        let job = makeJob(recorder: recorder, store: store, safetyArchivePath: nil)

        let error = runExpectingError(job)
        #expect(stderr(of: error).contains("Could not remove the current VM"))
        #expect(recorder.order == ["stop", "delete"]) // import never ran
    }

    /// End-to-end: the post-deletion import failure names the exact archive
    /// path and the re-import guidance, and the delete demonstrably ran
    /// before the import.
    @Test func importFailureGuidanceNamesArchivePathAfterDelete() {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.importError = TartClientError.commandFailed(
            command: "import", exitCode: 7, stdout: "", stderr: "bad archive")
        let job = makeJob(recorder: recorder, store: store, safetyArchivePath: nil)

        let error = runExpectingError(job)
        let message = stderr(of: error)
        #expect(message.contains("/snap/archive.tvm"))
        #expect(message.contains("Import…"))
        #expect(message.contains("bad archive")) // raw details appended
        #expect(recorder.order == ["stop", "delete", "import"])
        #expect(recorder.deletes == ["vm-a"])   // delete ran before the failing import
    }

    /// 200 000 chars streamed through a failing export surface as a bounded
    /// tail (TextAccumulator's 64 KiB cap), never the whole stream.
    @Test func boundedAccumulationCapsErrorDetails() {
        let (store, _) = makeStore()
        let recorder = Recorder()
        recorder.exportError = Boom()
        recorder.exportChunks = { onOutput in
            onOutput(String(repeating: "x", count: 200_000))
        }
        let job = makeJob(recorder: recorder, store: store,
                          safetyArchivePath: store.directory + "/safety.tvm")

        let error = runExpectingError(job)
        let message = stderr(of: error)
        #expect(message.contains("left untouched")) // safetyExport guidance
        #expect(message.count <= TextAccumulator.maxBufferedCharacters + 256)
    }

    /// A failed safety sidecar write aborts BEFORE the delete.
    @Test func safetySidecarWriteFailureAbortsBeforeDelete() {
        let store = SnapshotStore(directory: "/nonexistent/snapshots/x")
        let recorder = Recorder()
        let job = makeJob(recorder: recorder, store: store,
                          safetyArchivePath: store.directory + "/safety.tvm")

        let error = runExpectingError(job)
        #expect(stderr(of: error).contains("left untouched"))
        #expect(recorder.deletes.isEmpty) // delete never ran
        #expect(recorder.imports.isEmpty)
    }
}
