import Testing
import Foundation
@testable import TartKit

@Suite struct CreateFromIPSWJobTests {
    static func entry(name: String = "ipsw-vm", accessed: Date?) -> VMEntry {
        VMEntry(name: name, source: "local", running: false, state: "stopped",
                diskSize: 64, diskUsage: 10, accessed: accessed)
    }

    /// Thread-safe recorder for the injected ops (tests drive it synchronously;
    /// @Sendable closures capture it by reference).
    final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var listQueue: [Result<[VMEntry], TartClientError>] = []
        var createCalls: [(name: String, ipsw: String, diskSizeGB: Int)] = []
        var createResult: TartClient.CreateOutcome = .completed
        var createError: TartClientError?
        var deleted: [String] = []
        var anomalies: [TartClientError] = []
        var reported: [PullProgress] = []

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
                 startedAt: Date = Date(timeIntervalSince1970: 1_000)) -> CreateFromIPSWJob {
        CreateFromIPSWJob(
            name: "ipsw-vm",
            ipsw: "/Downloads/restore.ipsw",
            diskSizeGB: 50,
            startedAt: startedAt,
            ops: CreateFromIPSWJob.Ops(
                list: { try recorder.popList().get() },
                createFromIPSW: { name, ipsw, diskSizeGB, _, _ in
                    recorder.createCalls.append((name, ipsw, diskSizeGB))
                    if let error = recorder.createError { throw error }
                    return recorder.createResult
                },
                delete: { recorder.deleted.append($0) }),
            onCleanupAnomaly: { recorder.anomalies.append($0) })
    }

    @Test func preflightRejectsOccupiedNameWithoutLaunchingCreate() {
        let recorder = Recorder()
        recorder.enqueueList(.success([Self.entry(accessed: Date(timeIntervalSince1970: 500))]))
        let job = makeJob(recorder)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "create")
            #expect(exitCode == -1)
            #expect(stderr.contains("already exists"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(recorder.createCalls.isEmpty)
        #expect(recorder.deleted.isEmpty)
        #expect(recorder.anomalies.isEmpty)
    }

    @Test func successReportsIndeterminateProgressExactlyOnce() throws {
        // A restore's output has no parseable percentages — the job reports
        // the indeterminate form once and parses nothing.
        let recorder = Recorder()
        recorder.enqueueList(.success([]))
        let job = makeJob(recorder)
        try job.run(context: JobContext(report: { recorder.reported.append($0) }))
        #expect(recorder.createCalls.count == 1)
        #expect(recorder.reported == [PullProgress(fraction: nil, note: "installing…")])
        #expect(recorder.deleted.isEmpty)
        #expect(recorder.anomalies.isEmpty)
    }

    @Test func failureRunsCleanupAndRethrowsOriginalError() {
        let recorder = Recorder()
        recorder.enqueueList(.success([])) // pre-flight: free
        recorder.enqueueList(.success([Self.entry(accessed: Date(timeIntervalSince1970: 1_050))]))
        recorder.createError = TartClientError.commandFailed(command: "create", exitCode: 7,
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
        #expect(recorder.createCalls.count == 1)
        #expect(recorder.deleted == ["ipsw-vm"])
        #expect(recorder.anomalies.isEmpty)
    }

    @Test func collisionFailureSkipsCleanup() {
        let recorder = Recorder()
        recorder.enqueueList(.success([])) // pre-flight: free (launch race not yet visible)
        recorder.createError = TartClientError.commandFailed(
            command: "create", exitCode: 1, stdout: "",
            stderr: "VM with name \"ipsw-vm\" already exists")
        let job = makeJob(recorder)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch { }
        #expect(recorder.deleted.isEmpty)
        #expect(recorder.anomalies.isEmpty)
    }

    @Test func cancelledCreateCleansUpAndReturnsNormally() throws {
        let recorder = Recorder()
        recorder.enqueueList(.success([]))
        recorder.enqueueList(.success([Self.entry(accessed: Date(timeIntervalSince1970: 1_050))]))
        recorder.createResult = .cancelled
        let job = makeJob(recorder)
        try job.run(context: JobContext(report: { _ in }))
        #expect(recorder.deleted == ["ipsw-vm"])
        #expect(recorder.anomalies.isEmpty)
    }

    @Test func cleanupPreservesEntryOutsideJobWindow() {
        let recorder = Recorder()
        recorder.enqueueList(.success([]))
        recorder.enqueueList(.success([Self.entry(accessed: Date(timeIntervalSince1970: 900))]))
        recorder.createError = TartClientError.commandFailed(command: "create", exitCode: 5,
                                                             stdout: "", stderr: "boom")
        let job = makeJob(recorder)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch { }
        #expect(recorder.deleted.isEmpty)
        #expect(recorder.anomalies.count == 1)
        if case let .commandFailed(command, _, _, stderr) = recorder.anomalies[0] {
            #expect(command == "create-cleanup")
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
        recorder.createError = TartClientError.commandFailed(command: "create", exitCode: 5,
                                                             stdout: "", stderr: "boom")
        let job = makeJob(recorder)
        do {
            try job.run(context: JobContext(report: { _ in }))
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(_, exitCode, _, _) {
            #expect(exitCode == 5) // the create failure stays the job's error
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(recorder.deleted.isEmpty)
        #expect(recorder.anomalies == [listError])
    }
}
