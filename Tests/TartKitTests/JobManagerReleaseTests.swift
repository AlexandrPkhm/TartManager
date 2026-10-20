import Testing
import Foundation
@testable import TartKit

/// `JobManager` release of finished job records per `JobRetentionPolicy`.
@MainActor
@Suite struct JobManagerReleaseTests {
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func completedJobIsReleasedAfterTheDelay() async {
        let manager = JobManager(releaseDelay: .milliseconds(100))
        manager.start(kind: .clone(name: "vm-a", source: "img:latest")) { _ in }
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .completed)   // readable first
        await waitUntil(timeout: 2) { manager.jobs.isEmpty }
        #expect(manager.jobs.isEmpty)
    }

    @Test func cancelledJobIsReleasedAfterTheDelay() async {
        let manager = JobManager(releaseDelay: .milliseconds(100))
        let result = manager.start(kind: .exportSnapshot(vm: "vm-b")) { context in
            while !context.isCancelled { Thread.sleep(forTimeInterval: 0.01) }
        }
        guard case .started(let job) = result else {
            Issue.record("expected .started, got \(result)")
            return
        }
        manager.cancel(id: job.id)
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .cancelled)
        await waitUntil(timeout: 2) { manager.jobs.isEmpty }
        #expect(manager.jobs.isEmpty)
    }

    @Test func failedJobStaysUntilDismissed() async {
        let manager = JobManager(releaseDelay: .milliseconds(50))
        let result = manager.start(kind: .clone(name: "vm-c", source: "bad:ref")) { _ in
            throw TartClientError.commandFailed(command: "clone", exitCode: 1,
                                                stdout: "", stderr: "Error: no such image")
        }
        guard case .started(let job) = result else {
            Issue.record("expected .started, got \(result)")
            return
        }
        await manager.awaitIdle(timeout: 2)
        try? await Task.sleep(for: .milliseconds(300))
        #expect(manager.jobs.first?.phase == .failed)
        manager.dismiss(id: job.id)
        #expect(manager.jobs.isEmpty)
    }

    @Test func defaultDelayKeepsAFinishedRecordReadable() async {
        let manager = JobManager()
        manager.start(kind: .clone(name: "vm-d", source: "img:latest")) { _ in }
        await manager.awaitIdle(timeout: 2)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(manager.jobs.first?.phase == .completed)
    }
}
