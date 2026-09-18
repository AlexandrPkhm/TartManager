import Testing
import Foundation
@testable import TartKit

@Suite struct SnapshotServiceTests {
    @Test func configuredFolderWinsOverDefault() {
        #expect(SnapshotService.resolveDirectory(storagePath: "/Volumes/SSD/Work/VMs/Tart",
                                                 configuredFolder: "/Volumes/Archive/Snaps")
                == "/Volumes/Archive/Snaps")
    }

    @Test func defaultIsSiblingOfStorageOnTheSameVolume() {
        #expect(SnapshotService.resolveDirectory(storagePath: "/Volumes/SSD/Work/VMs/Tart",
                                                 configuredFolder: nil)
                == "/Volumes/SSD/Work/VMs/Snapshots")
    }

    /// finding 8: no storage path and no configured folder ⇒ nil, never a
    /// volatile temp-directory fallback.
    @Test func noStorageMeansNilNotTempFallback() {
        #expect(SnapshotService.resolveDirectory(storagePath: nil, configuredFolder: nil) == nil)
    }
}

@Suite struct SnapshotCreateJobTests {
    static func entry(_ name: String, running: Bool) -> VMEntry {
        VMEntry(name: name, source: "local", running: running,
                state: running ? "running" : "stopped",
                diskSize: 64, diskUsage: 20, accessed: nil)
    }

    func makeStore() -> (store: SnapshotStore, directory: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return (SnapshotStore(directory: dir.path), dir.path)
    }

    /// Thread-safe recorder for the injected ops.
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var listQueue: [Result<[VMEntry], TartClientError>] = []
        var ensuredDirectories: [String] = []
        var exports: [(name: String, path: String)] = []
        var exportResult: TartClient.ExportOutcome = .completed
        var exportError: TartClientError?
        var reportedProgress: [PullProgress] = []

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

    func makeJob(recorder: Recorder, store: SnapshotStore,
                 archivePath: String) -> SnapshotCreateJob {
        SnapshotCreateJob(
            vmName: "vm-a", label: "pre", archivePath: archivePath,
            createdAt: Date(timeIntervalSince1970: 1_000),
            directory: store.directory, store: store,
            ops: SnapshotCreateJob.Ops(
                ensureDirectory: { recorder.ensuredDirectories.append($0) },
                list: { try recorder.popList().get() },
                export: { name, path, onOutput, _ in
                    recorder.exports.append((name, path))
                    onOutput("raw output — not parsed")
                    if let error = recorder.exportError { throw error }
                    return recorder.exportResult
                }))
    }

    /// finding 4 (automated): the pipeline issues the correct export to the
    /// correct path/filename and leaves a complete catalog entry on success.
    @Test func createPipelineExportsToTheProposedPathAndWritesMetadata() throws {
        let (store, _) = makeStore()
        let archivePath = store.proposeArchivePath(
            vmName: "vm-a", label: "pre", date: Date(timeIntervalSince1970: 1_000))
        FileManager.default.createFile(atPath: archivePath, contents: Data(count: 128))
        let recorder = Recorder()
        recorder.enqueueList(.success([Self.entry("vm-a", running: false)]))
        let job = makeJob(recorder: recorder, store: store, archivePath: archivePath)
        try job.run(context: JobContext(report: { recorder.reportedProgress.append($0) }))

        #expect(recorder.ensuredDirectories == [store.directory])
        #expect(recorder.exports.count == 1)
        #expect(recorder.exports[0].name == "vm-a")
        #expect(recorder.exports[0].path == archivePath)
        // finding 10: exactly one indeterminate report, never parsed progress.
        #expect(recorder.reportedProgress == [PullProgress(fraction: nil, note: "exporting…")])
        let snapshots = try store.snapshots(forVM: "vm-a")
        #expect(snapshots.count == 1)
        #expect(snapshots[0].archivePath == archivePath)
        #expect(snapshots[0].label == "pre")
    }

    /// stopped-only enforcement, re-verified on a fresh list: a running VM
    /// must terminate the job before any export is launched.
    @Test func runningVMTerminatesWithoutExporting() throws {
        let (store, _) = makeStore()
        let archivePath = store.proposeArchivePath(vmName: "vm-a", label: "pre")
        let recorder = Recorder()
        recorder.enqueueList(.success([Self.entry("vm-a", running: true)]))
        let job = makeJob(recorder: recorder, store: store, archivePath: archivePath)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "export")
            #expect(exitCode == -1)
            #expect(stderr.contains("running"))
        }
        #expect(recorder.exports.isEmpty)
        #expect(try store.snapshots().isEmpty)
    }

    /// failure path leaves the catalog consistent: no sidecar is written and
    /// the partial archive (if tart left one) is an unowned entry that never
    /// matches the VM (finding 7).
    @Test func exportFailureLeavesCatalogConsistent() throws {
        let (store, _) = makeStore()
        let archivePath = store.proposeArchivePath(vmName: "vm-a", label: "pre")
        FileManager.default.createFile(atPath: archivePath, contents: Data(count: 128))
        let recorder = Recorder()
        recorder.enqueueList(.success([Self.entry("vm-a", running: false)]))
        recorder.exportError = TartClientError.commandFailed(command: "export", exitCode: 7,
                                                             stdout: "", stderr: "disk full")
        let job = makeJob(recorder: recorder, store: store, archivePath: archivePath)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(_, exitCode, _, _) {
            #expect(exitCode == 7)
        }
        #expect(try store.snapshots(forVM: "vm-a").isEmpty) // no phantom per-VM entry
        let all = try store.snapshots()
        #expect(all.count == 1)
        #expect(all[0].vmName == "unknown")                 // unowned, not invisible
    }

    /// cancel path writes no sidecar.
    @Test func cancelledExportWritesNoSidecar() throws {
        let (store, _) = makeStore()
        let archivePath = store.proposeArchivePath(vmName: "vm-a", label: "pre")
        let recorder = Recorder()
        recorder.enqueueList(.success([Self.entry("vm-a", running: false)]))
        recorder.exportResult = .cancelled
        let job = makeJob(recorder: recorder, store: store, archivePath: archivePath)
        try job.run(context: JobContext(report: { _ in }))
        #expect(try store.snapshots(forVM: "vm-a").isEmpty)
    }
}
