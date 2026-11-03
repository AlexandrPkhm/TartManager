import Testing
import Foundation
@testable import TartKit

@Suite struct VMDeleteJobTests {
    func entry(_ name: String, state: String, running: Bool) -> VMEntry {
        VMEntry(name: name, source: "local", running: running, state: state,
                diskSize: 50, diskUsage: 50, accessed: nil)
    }

    /// Thread-safe list queue + delete recorder for the injected ops
    /// (unchecked: tests drive it synchronously; @Sendable closures capture
    /// it by reference).
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var listQueue: [Result<[VMEntry], TartClientError>] = []
        var deleteCalls: [(name: String, timeout: TimeInterval)] = []
        var deleteError: TartClientError?
        var keepError: Error?
        var keptDisks: [String] = []
        var discardedDisks: [String] = []

        func enqueueList(_ call: Result<[VMEntry], TartClientError>) {
            lock.lock(); defer { lock.unlock() }
            listQueue.append(call)
        }

        func popList() -> Result<[VMEntry], TartClientError> {
            lock.lock(); defer { lock.unlock() }
            return listQueue.isEmpty ? .success([]) : listQueue.removeFirst()
        }
    }

    func makeJob(_ recorder: Recorder, keepDisk: Bool = false) -> VMDeleteJob {
        VMDeleteJob(name: "vm-a", keepDisk: keepDisk, ops: VMDeleteJob.Ops(
            list: { try recorder.popList().get() },
            delete: { name, timeout in
                recorder.deleteCalls.append((name, timeout))
                if let error = recorder.deleteError { throw error }
            },
            keepDisk: { name in
                if let error = recorder.keepError { throw error }
                recorder.keptDisks.append(name)
                return "/kept/\(name).img"
            },
            discardKeptDisk: { path in recorder.discardedDisks.append(path) }))
    }

    @Test func stoppedVMDeletesWithTheBoundTimeout() throws {
        let recorder = Recorder()
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        try makeJob(recorder).run(context: JobContext(report: { _ in }))
        #expect(recorder.deleteCalls.count == 1)
        #expect(recorder.deleteCalls[0].name == "vm-a")
        // Finding 3: the uncancellable delete is bounded by the documented
        // watchdog timeout — asserted here so the bound cannot silently drift.
        #expect(recorder.deleteCalls[0].timeout == VMDeleteJob.deleteTimeout)
    }

    @Test func absentVMAtLaunchIsACleanNoOp() throws {
        // Race tolerance before spawn: the VM was deleted externally between
        // the poll and the job — no delete is issued, no error surfaces.
        let recorder = Recorder()
        recorder.enqueueList(.success([]))
        try makeJob(recorder).run(context: JobContext(report: { _ in }))
        #expect(recorder.deleteCalls.isEmpty)
    }

    @Test func runningOrSuspendedVMIsRefusedBeforeSpawn() throws {
        // AC2 automated: a VM that is (or became) running or suspended is
        // refused before any subprocess — the injected delete op is never
        // invoked (marker: no recorded calls).
        for fixture in [entry("vm-a", state: "running", running: true),
                        entry("vm-a", state: "suspended", running: false)] {
            let recorder = Recorder()
            recorder.enqueueList(.success([fixture]))
            do {
                try makeJob(recorder).run(context: JobContext(report: { _ in }))
                Issue.record("expected refusal for \(fixture.state)")
            } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
                #expect(command == "delete")
                #expect(exitCode == -1)
                #expect(stderr.contains("Stop the VM first"))
            }
            #expect(recorder.deleteCalls.isEmpty)
        }
    }

    @Test func failedDeleteOfAVanishedVMReconcilesAsNoOp() throws {
        // The issue's mandated race reconciliation: the delete target
        // disappears mid-action → clean no-op (fresh re-list), no error.
        let recorder = Recorder()
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        recorder.deleteError = TartClientError.commandFailed(command: "delete", exitCode: 4,
                                                             stdout: "", stderr: "not found")
        recorder.enqueueList(.success([])) // fresh re-list: gone
        try makeJob(recorder).run(context: JobContext(report: { _ in }))
        #expect(recorder.deleteCalls.count == 1)
    }

    @Test func failedDeleteOfAStillPresentVMRethrows() throws {
        let recorder = Recorder()
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        recorder.deleteError = TartClientError.commandFailed(command: "delete", exitCode: 4,
                                                             stdout: "", stderr: "disk error")
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        do {
            try makeJob(recorder).run(context: JobContext(report: { _ in }))
            Issue.record("expected rethrow")
        } catch let TartClientError.commandFailed(_, exitCode, _, stderr) {
            #expect(exitCode == 4)
            #expect(stderr.contains("disk error"))
        }
    }

    // MARK: Keep the disk

    private func stoppedRecorder() -> Recorder {
        let recorder = Recorder()
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        return recorder
    }

    @Test func removingTheDiskKeepsNothing() throws {
        let recorder = stoppedRecorder()
        try makeJob(recorder).run(context: JobContext(report: { _ in }))
        #expect(recorder.keptDisks.isEmpty)
        #expect(recorder.deleteCalls.count == 1)
    }

    @Test func keepingTheDiskSavesItAndThenDeletes() throws {
        let recorder = stoppedRecorder()
        try makeJob(recorder, keepDisk: true).run(context: JobContext(report: { _ in }))
        #expect(recorder.keptDisks == ["vm-a"])
        #expect(recorder.deleteCalls.count == 1)
        #expect(recorder.discardedDisks.isEmpty)
    }

    @Test func failedKeepRefusesTheDelete() {
        struct KeepFailure: Error {}
        let recorder = stoppedRecorder()
        recorder.keepError = KeepFailure()
        do {
            try makeJob(recorder, keepDisk: true).run(context: JobContext(report: { _ in }))
            Issue.record("expected refusal")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "delete")
            #expect(exitCode == -1)
            #expect(stderr.contains("cannot keep the disk"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(recorder.deleteCalls.isEmpty)
    }

    @Test func failedDeleteDiscardsTheKeptDisk() {
        let recorder = stoppedRecorder()
        recorder.deleteError = TartClientError.commandFailed(command: "delete", exitCode: 4,
                                                             stdout: "", stderr: "disk error")
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        #expect(throws: TartClientError.self) {
            try makeJob(recorder, keepDisk: true).run(context: JobContext(report: { _ in }))
        }
        #expect(recorder.discardedDisks == ["/kept/vm-a.img"])
    }

    @Test func vanishedVMKeepsTheKeptDisk() throws {
        let recorder = stoppedRecorder()
        recorder.deleteError = TartClientError.commandFailed(command: "delete", exitCode: 4,
                                                             stdout: "", stderr: "not found")
        recorder.enqueueList(.success([]))
        try makeJob(recorder, keepDisk: true).run(context: JobContext(report: { _ in }))
        #expect(recorder.discardedDisks.isEmpty)
    }

    @Test func absentVMKeepsNoDisk() throws {
        let recorder = Recorder()
        recorder.enqueueList(.success([]))
        try makeJob(recorder, keepDisk: true).run(context: JobContext(report: { _ in }))
        #expect(recorder.keptDisks.isEmpty)
    }

    @Test func timedOutDeleteFailsTheJobForTheSurfacePath() {
        // Finding 3: a wedged tart is terminated by the ProcessRunner
        // deadline inside TartClient.delete and surfaces as .timedOut; the
        // job rethrows it (the VM is still present) so the standard
        // onStateChange sheet presents the failure.
        let recorder = Recorder()
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        recorder.deleteError = TartClientError.timedOut(command: "delete",
                                                        timeout: VMDeleteJob.deleteTimeout)
        recorder.enqueueList(.success([entry("vm-a", state: "stopped", running: false)]))
        do {
            try makeJob(recorder).run(context: JobContext(report: { _ in }))
            Issue.record("expected rethrow")
        } catch let error as TartClientError {
            guard case .timedOut = error else {
                Issue.record("expected .timedOut, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
