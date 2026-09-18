import Testing
import Foundation
@testable import TartKit

@Suite struct ImportJobTests {
    static func entry(name: String = "partial-junk", accessed: Date?) -> VMEntry {
        VMEntry(name: name, source: "local", running: false, state: "stopped",
                diskSize: 64, diskUsage: 10, accessed: accessed)
    }

    /// Thread-safe recorder for the injected ops (unchecked: tests drive it
    /// synchronously; @Sendable closures capture it by reference).
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var listQueue: [Result<[VMEntry], TartClientError>] = []
        var importCalls: [(path: String, name: String)] = []
        var importResult: TartClient.ImportOutcome = .completed
        var importError: TartClientError?
        var deleted: [String] = []
        var anomalies: [TartClientError] = []

        func enqueueList(_ call: Result<[VMEntry], TartClientError>) {
            lock.lock(); defer { lock.unlock() }
            listQueue.append(call)
        }

        func popList() -> Result<[VMEntry], TartClientError> {
            lock.lock(); defer { lock.unlock() }
            return listQueue.isEmpty ? .success([]) : listQueue.removeFirst()
        }
    }

    func makeJob(_ recorder: Recorder,
                 startedAt: Date = Date(timeIntervalSince1970: 1_000)) -> ImportJob {
        ImportJob(
            name: "partial-junk",
            path: "/tmp/archive.tvm",
            startedAt: startedAt,
            ops: ImportJob.Ops(
                list: { try recorder.popList().get() },
                importArchive: { path, name, _, _ in
                    recorder.importCalls.append((path, name))
                    if let error = recorder.importError { throw error }
                    return recorder.importResult
                },
                delete: { recorder.deleted.append($0) }),
            onCleanupAnomaly: { recorder.anomalies.append($0) })
    }

    @Test func preflightRejectsOccupiedNameWithoutLaunchingImport() {
        let recorder = Recorder()
        recorder.enqueueList(.success([Self.entry(accessed: Date(timeIntervalSince1970: 500))]))
        let job = makeJob(recorder)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "import")
            #expect(exitCode == -1)
            #expect(stderr.contains("already exists"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(recorder.importCalls.isEmpty)
        #expect(recorder.deleted.isEmpty)
        #expect(recorder.anomalies.isEmpty)
    }

    @Test func failureRunsCleanupAndRethrowsOriginalError() {
        let recorder = Recorder()
        recorder.enqueueList(.success([])) // pre-flight: free
        recorder.enqueueList(.success([Self.entry(accessed: Date(timeIntervalSince1970: 1_050))]))
        recorder.importError = TartClientError.commandFailed(command: "import", exitCode: 7,
                                                             stdout: "", stderr: "disk full")
        let job = makeJob(recorder)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(_, exitCode, _, stderr) {
            #expect(exitCode == 7)
            #expect(stderr.contains("disk full"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(recorder.importCalls.count == 1)
        #expect(recorder.deleted == ["partial-junk"])
        #expect(recorder.anomalies.isEmpty)
    }

    @Test func collisionFailureSkipsCleanup() {
        let recorder = Recorder()
        recorder.enqueueList(.success([])) // pre-flight: free (launch race not yet visible)
        recorder.importError = TartClientError.commandFailed(
            command: "import", exitCode: 1, stdout: "",
            stderr: "VM with name \"partial-junk\" already exists")
        let job = makeJob(recorder)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch { }
        #expect(recorder.deleted.isEmpty)
        #expect(recorder.anomalies.isEmpty)
    }

    @Test func cancelledImportCleansUpAndReturnsNormally() throws {
        let recorder = Recorder()
        recorder.enqueueList(.success([]))
        recorder.enqueueList(.success([Self.entry(accessed: Date(timeIntervalSince1970: 1_050))]))
        recorder.importResult = .cancelled
        let job = makeJob(recorder)
        try job.run(context: JobContext(report: { _ in }))
        #expect(recorder.deleted == ["partial-junk"])
        #expect(recorder.anomalies.isEmpty)
    }

    @Test func cleanupPreservesEntryOutsideJobWindow() {
        let recorder = Recorder()
        recorder.enqueueList(.success([]))
        recorder.enqueueList(.success([Self.entry(accessed: Date(timeIntervalSince1970: 900))]))
        recorder.importError = TartClientError.commandFailed(command: "import", exitCode: 5,
                                                             stdout: "", stderr: "boom")
        let job = makeJob(recorder)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch { }
        #expect(recorder.deleted.isEmpty)
        #expect(recorder.anomalies.count == 1)
        if case let .commandFailed(command, _, _, stderr) = recorder.anomalies[0] {
            #expect(command == "import-cleanup")
            #expect(stderr.contains("left untouched"))
        } else {
            Issue.record("expected a commandFailed preservation notice")
        }
    }

    @Test func cleanupListFailureSurfacesAnomalyAndKeepsOriginalError() {
        let recorder = Recorder()
        recorder.enqueueList(.success([]))
        let listError = TartClientError.commandFailed(command: "list", exitCode: 2,
                                                      stdout: "", stderr: "storage unavailable")
        recorder.enqueueList(.failure(listError))
        recorder.importError = TartClientError.commandFailed(command: "import", exitCode: 5,
                                                             stdout: "", stderr: "boom")
        let job = makeJob(recorder)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(_, exitCode, _, _) {
            #expect(exitCode == 5) // the import failure stays the job's error
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(recorder.deleted.isEmpty)
        #expect(recorder.anomalies == [listError])
    }
}
