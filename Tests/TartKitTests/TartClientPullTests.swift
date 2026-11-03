import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientPullTests {
    private func makeClient(stub: String) -> TartClient {
        TartClient(binaryPath: stub,
                   environment: TartCommandEnvironment(storagePath: "/tmp/pull-home").environment)
    }

    /// Thread-safe collector for the progress callbacks.
    final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [PullProgress] = []

        func append(_ value: PullProgress) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        var all: [PullProgress] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    final class ActionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var action: (() -> Void)?

        func set(_ action: @escaping () -> Void) {
            lock.lock()
            self.action = action
            lock.unlock()
        }

        func take() -> (() -> Void)? {
            lock.lock()
            defer { lock.unlock() }
            return action
        }
    }

    @Test func pullSendsReferenceAndStorageEnvironment() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nexit 0\n")
        let capture = URL(fileURLWithPath: stub).deletingLastPathComponent()
            .appendingPathComponent("captured.txt").path
        try """
        #!/bin/sh
        echo "$TART_HOME $@" > '\(capture)'
        exit 0
        """.write(toFile: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)

        let exit = try makeClient(stub: stub).pull(
            reference: "ghcr.io/cirruslabs/macos-tahoe-base:latest", onProgress: { _ in })
        #expect(exit == .completed)
        let lines = try CaptureFile.waitForLines(atPath: capture, count: 1)
        #expect(lines == ["/tmp/pull-home pull ghcr.io/cirruslabs/macos-tahoe-base:latest"])
    }

    @Test func pullReportsProgress() throws {
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo 'pulling disk (27.3 GB compressed)...'
        echo '14%'
        echo '50%'
        exit 0
        """)
        let box = ProgressBox()
        _ = try makeClient(stub: stub).pull(reference: "img:latest", onProgress: { box.append($0) })
        #expect(box.all.last?.fraction == 0.5)
    }

    @Test func pullFailureCarriesTartMessageAndPullLabel() {
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo 'pulling manifest...'
        echo 'Error: manifest unknown: nope'
        exit 1
        """)
        do {
            _ = try makeClient(stub: stub).pull(reference: "img:missing", onProgress: { _ in })
            Issue.record("expected pull to throw")
        } catch let error as TartClientError {
            #expect(error.normalized.operation == "pull")
            #expect(error.normalized.message == "manifest unknown: nope")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func pullLaunchFailureCarriesPullLabel() {
        do {
            _ = try makeClient(stub: "/nonexistent/tart").pull(reference: "img:latest", onProgress: { _ in })
            Issue.record("expected pull to throw")
        } catch let error as TartClientError {
            #expect(error.normalized.operation == "pull")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func pullRejectsLeadingDashBeforeSpawn() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        #expect(throws: TartClientError.self) {
            _ = try makeClient(stub: stub).pull(reference: "--help", onProgress: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }

    @Test func pullReportsCancelledWhenCancelActionRuns() async throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = makeClient(stub: stub)
        let box = ActionBox()
        let task = Task.detached {
            try client.pull(reference: "img:latest", onProgress: { _ in },
                            registerCancel: { box.set($0) })
        }
        for _ in 0..<100 where box.take() == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        box.take()?()
        let result = try await task.value
        #expect(result == .cancelled)
    }

    @MainActor @Test func startPullRefusesTheSameImageWhileRunning() async {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let manager = JobManager()
        let client = makeClient(stub: stub)
        let first = manager.startPull(reference: "img:latest", using: client)
        #expect(first != nil)
        #expect(manager.startPull(reference: "img:latest", using: client) == nil)
        if let first { manager.cancel(id: first.id) }
        await manager.awaitIdle(timeout: 10)
        #expect(manager.jobs.first?.phase == .cancelled)
    }

    @Test func pullKindDerivesTargetOperationAndEstimate() {
        let kind = JobInfo.Kind.pull(reference: "img:latest")
        #expect(kind.target == "pull:img:latest")
        #expect(kind.operation == "pull")
        #expect(kind.isCancellable)
        #expect(kind.estimatedDiskNeedBytes == DiskSpacePolicy.remoteImageEstimateBytes)
    }
}
