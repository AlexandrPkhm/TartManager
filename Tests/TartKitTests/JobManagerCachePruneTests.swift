import Foundation
import Testing
@testable import TartKit

@MainActor
@Suite struct JobManagerCachePruneTests {
    @Test func regularJobReservesTargetButWaitsForCacheCleanupBeforeBody() async {
        let manager = JobManager()
        let pruneGate = AsyncGate()
        defer { pruneGate.open() }
        manager.start(kind: .prune) { _ in
            while !pruneGate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
        }
        let executed = LockedValue(false)
        let result = manager.start(kind: .clone(name: "queued-vm", source: "image")) { _ in
            executed.withValue { $0 = true }
        }
        guard case .started(let queued) = result else {
            Issue.record("A normal job should reserve its target while cache cleanup is running.")
            return
        }
        await waitFor(manager: manager, jobID: queued.id) {
            $0.progress?.note == "Waiting for cache cleanup…" || $0.phase != .running
        }
        #expect(manager.runningTargets == ["prune:caches", "queued-vm"])
        #expect(manager.jobs.first(where: { $0.id == queued.id })?.progress?.note ==
                "Waiting for cache cleanup…")
        #expect(!executed.value)

        pruneGate.open()
        await manager.awaitIdle(timeout: 2)
        #expect(executed.value)
        #expect(manager.jobs.first(where: { $0.id == queued.id })?.phase == .completed)
        #expect(manager.jobs.first(where: { $0.id == queued.id })?.progress?.note !=
                "Waiting for cache cleanup…")
    }

    @Test func cancellingWaitingJobFinishesBeforePruneWithoutRunningBody() async {
        let manager = JobManager()
        let pruneGate = AsyncGate()
        defer { pruneGate.open() }
        manager.start(kind: .prune) { _ in
            while !pruneGate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
        }
        let executed = LockedValue(false)
        let result = manager.start(kind: .clone(name: "cancelled-vm", source: "image")) { _ in
            executed.withValue { $0 = true }
        }
        guard case .started(let queued) = result else {
            Issue.record("A normal job should reserve its target while cache cleanup is running.")
            return
        }
        await waitFor(manager: manager, jobID: queued.id) {
            $0.progress?.note == "Waiting for cache cleanup…" || $0.phase != .running
        }
        manager.cancel(id: queued.id)
        await waitFor(manager: manager, jobID: queued.id) { $0.phase != .running }
        #expect(!executed.value)
        #expect(manager.jobs.first(where: { $0.id == queued.id })?.phase == .cancelled)
        #expect(manager.jobs.first(where: { $0.kind == .prune })?.phase == .running)
        #expect(manager.runningTargets == ["prune:caches"])

        pruneGate.open()
        await manager.awaitIdle(timeout: 2)
    }

    private func waitFor(manager: JobManager, jobID: UUID,
                         condition: (JobInfo) -> Bool) async {
        for _ in 0..<200 {
            if let job = manager.jobs.first(where: { $0.id == jobID }), condition(job) { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the queued job state.")
    }
}
