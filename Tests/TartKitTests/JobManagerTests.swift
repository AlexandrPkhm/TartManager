import Testing
import Foundation
@testable import TartKit

@MainActor
@Suite struct JobManagerTests {
    @Test func startCreatesRunningJobAndCompletesIt() async {
        let manager = JobManager()
        let result = manager.start(kind: .clone(name: "vm-a", source: "img:latest")) { context in
            context.report(PullProgress(fraction: 0.5, note: nil))
        }
        guard case .started(let job) = result else {
            Issue.record("expected .started, got \(result)")
            return
        }
        #expect(job.kind.target == "vm-a")          // finding 5: derived from the kind
        #expect(manager.jobs.first?.phase == .running)
        #expect(manager.runningTargets == ["vm-a"])
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .completed)
        #expect(manager.jobs.first?.progress?.fraction == 0.5)
        #expect(manager.runningTargets.isEmpty)
    }

    @Test func failingBodyMarksJobFailedWithNormalizedError() async {
        let manager = JobManager()
        manager.start(kind: .clone(name: "vm-b", source: "bad:ref")) { _ in
            throw TartClientError.commandFailed(command: "clone", exitCode: 1,
                                                stdout: "", stderr: "Error: no such image")
        }
        await manager.awaitIdle(timeout: 2)
        let job = manager.jobs.first
        #expect(job?.phase == .failed)
        #expect(job?.error?.message == "no such image")
    }

    @Test func unknownThrownErrorUsesKindOperationLabel() async {
        // finding 16: the generic wrap labels the failure with the job
        // kind's operation ("clone"), never a bare "job".
        struct StubError: Error {}
        let manager = JobManager()
        manager.start(kind: .clone(name: "vm-e", source: "x:y")) { _ in
            throw StubError()
        }
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.error?.operation == "clone")
    }

    @Test func cancelTerminatesBodyAndMarksCancelled() async throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let manager = JobManager()
        manager.start(kind: .clone(name: "vm-c", source: "x:y")) { context in
            let process = try StreamingProcess.launch(
                binaryPath: stub, arguments: [], environment: [:]) { _ in }
            context.registerCancel { process.cancel() }
            _ = process.waitForExit()
        }
        try await Task.sleep(for: .seconds(0.3))
        let id = manager.jobs[0].id
        manager.cancel(id: id)
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .cancelled)
    }

    @Test func secondJobForSameTargetReturnsDuplicateTarget() async {
        // findings 4/5: the target comes from the kind; the refusal is an
        // observable result the caller can surface, not a silent nil.
        let manager = JobManager()
        let gate = AsyncGate()
        manager.start(kind: .clone(name: "vm-d", source: "a:b")) { _ in
            while !gate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
        }
        let second = manager.start(kind: .clone(name: "vm-d", source: "a:b")) { _ in }
        guard case .duplicateTarget(let target) = second else {
            Issue.record("expected .duplicateTarget, got \(second)")
            return
        }
        #expect(target == "vm-d")
        gate.open()
        await manager.awaitIdle(timeout: 2)
    }

    @Test func progressReportsDedupe() async {
        // finding 12 (manager side): identical reports do not republish.
        let manager = JobManager()
        manager.start(kind: .clone(name: "vm-f", source: "x:y")) { context in
            let first = PullProgress(fraction: 0.1, note: nil)
            context.report(first)
            context.report(first)
            context.report(PullProgress(fraction: 0.2, note: nil))
        }
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.progress?.fraction == 0.2)
    }

    @Test func preflightSpaceMapsKindEstimates() {
        // finding 8: the pre-flight decision lives in the Job Manager, not
        // in the App UI.
        let kind = JobInfo.Kind.clone(name: "vm-g", source: "x:y")
        #expect(JobManager.preflightSpace(kind: kind, freeBytes: 1_000_000_000_000)
                == .ok(freeBytes: 1_000_000_000_000))
        #expect(JobManager.preflightSpace(kind: kind, freeBytes: 1)
                == .tight(freeBytes: 1,
                          estimatedNeedBytes: DiskSpacePolicy.remoteImageEstimateBytes))
        #expect(JobManager.preflightSpace(kind: kind, freeBytes: nil) == nil)
    }

    @Test func activeTargetsTracksRunningJobs() async {
        let manager = JobManager()
        let gate = AsyncGate()
        manager.start(kind: .clone(name: "vm-e", source: "a:b")) { _ in
            while !gate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
        }
        #expect(manager.activeTargets.contains("vm-e"))
        gate.open()
        await manager.awaitIdle(timeout: 2)
        #expect(manager.activeTargets.isEmpty)
    }

    @Test func exportSnapshotKindDerivesTargetAndOperation() {
        let kind = JobInfo.Kind.exportSnapshot(vm: "vm-a")
        #expect(kind.target == "vm-a")
        #expect(kind.operation == "export")
        // The export estimate needs the VM's on-disk size (not carried by the
        // case): pre-flights use DiskSpacePolicy.exportVerdict instead.
        #expect(kind.estimatedDiskNeedBytes == nil)
    }

    @Test func restoreSnapshotKindDerivesTargetAndOperation() {
        let kind = JobInfo.Kind.restoreSnapshot(vm: "vm-a")
        #expect(kind.target == "vm-a")
        #expect(kind.operation == "restore")
        // The composite restore estimate needs data the case does not
        // carry — the pre-flight lives in SnapshotRestoreJob.
        #expect(kind.estimatedDiskNeedBytes == nil)
        // Restore is not cancellable.
        #expect(kind.isCancellable == false)
    }

    @Test func cancelIsIgnoredForRestoreJobs() async {
        // A restore must never be marked cancelled while its destructive
        // pipeline runs — cancel is suppressed at the source.
        final class Flag: @unchecked Sendable {
            private let lock = NSLock()
            private var _completed = false
            var isCompleted: Bool {
                lock.lock(); defer { lock.unlock() }
                return _completed
            }
            func complete() {
                lock.lock(); _completed = true; lock.unlock()
            }
        }
        let manager = JobManager()
        let gate = AsyncGate()
        let completed = Flag()
        let result = manager.start(kind: .restoreSnapshot(vm: "vm-r")) { _ in
            while !gate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
            completed.complete()
        }
        guard case .started(let info) = result else {
            Issue.record("job not found"); return
        }
        manager.cancel(id: info.id)
        gate.open()
        await manager.awaitIdle(timeout: 2)
        #expect(completed.isCompleted)
        let finished = manager.jobs.first { $0.id == info.id }
        #expect(finished?.phase == .completed) // never .cancelled
    }

    @Test func deleteVMKindDerivesTargetOperationAndCancellability() {
        let kind = JobInfo.Kind.deleteVM(name: "vm-a")
        #expect(kind.target == "vm-a")
        #expect(kind.operation == "delete")
        #expect(kind.estimatedDiskNeedBytes == nil)
        // The policy: deletion is not cancellable — killing a partially
        // removed VM directory would be the ghost entry the PRD forbids.
        #expect(kind.isCancellable == false)
    }

    @Test func cancelIsIgnoredForDeleteJobs() async {
        // A delete must never be marked cancelled midway: the manager
        // refuses at the source (the Issue 15 restore guarantee, extended
        // to the deleteVM kind).
        let manager = JobManager()
        let gate = AsyncGate()
        var deleteCompleted = false
        let result = manager.start(kind: .deleteVM(name: "vm-a")) { _ in
            while !gate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
            deleteCompleted = true
        }
        guard case .started(let info) = result else {
            Issue.record("job not found"); return
        }
        manager.cancel(id: info.id)
        gate.open()
        await manager.awaitIdle(timeout: 2)
        #expect(deleteCompleted)
        let finished = manager.jobs.first { $0.id == info.id }
        #expect(finished?.phase == .completed) // never .cancelled
    }

    @Test func replaceDiskJobsAreNotCancellable() {
        // Finding 3: killing a `set --disk` halfway corrupts the VM's disk —
        // the same data-unsafety rule as delete/restore (Issue 17).
        #expect(JobInfo.Kind.replaceDisk(name: "vm-a", path: "/images/clean.img")
            .isCancellable == false)
        #expect(JobInfo.Kind.deleteVM(name: "vm-a").isCancellable == false)
        #expect(JobInfo.Kind.restoreSnapshot(vm: "vm-a").isCancellable == false)
        #expect(JobInfo.Kind.clone(name: "vm-b", source: "x:y").isCancellable == true)
    }

    @Test func replaceDiskKindDerivesTargetOperationAndEstimate() {
        let kind = JobInfo.Kind.replaceDisk(name: "vm-a", path: "/images/clean.img")
        #expect(kind.target == "vm-a")
        #expect(kind.operation == "set")
        // No pre-flight estimate: the source file is chosen ad hoc and PRD
        // Story 14's space pre-check covers clone/import/export only.
        #expect(kind.estimatedDiskNeedBytes == nil)
    }

    @Test func cancelIsNoOpForReplaceDiskJobs() async {
        let manager = JobManager()
        let gate = AsyncGate()
        manager.start(kind: .replaceDisk(name: "vm-a", path: "/images/clean.img")) { _ in
            while !gate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
        }
        let id = manager.jobs[0].id
        manager.cancel(id: id)
        try? await Task.sleep(for: .seconds(0.1))
        #expect(manager.jobs.first?.phase == .running) // refused, not cancelled
        gate.open()
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .completed)
    }
    @Test @MainActor func pruneIsCancellable() {
        #expect(JobInfo.Kind.prune.isCancellable == true)
    }

    /// finding 5: the single-flight key is namespaced so it can never
    /// collide with a VM named "caches"; finding 8: the operation label is
    /// "prune"; prune frees space, so there is no pre-flight estimate.
    @Test @MainActor func pruneKindDerivedMembers() {
        let kind = JobInfo.Kind.prune
        #expect(kind.target == "prune:caches")
        #expect(kind.operation == "prune")
        #expect(kind.estimatedDiskNeedBytes == nil)
    }

    @Test @MainActor func jobBodiesCanReportCompletionSummaries() async {
        let manager = JobManager()
        manager.start(kind: .prune) { context in
            context.reportSummary("Removed 4 entries, freed 46 GB")
        }
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .completed)
        #expect(manager.jobs.first?.summary == "Removed 4 entries, freed 46 GB")
    }

    /// finding 3: a body that reports a summary and then throws must leave
    /// NO summary on the failed job — the buffer is discarded on every
    /// non-successful terminal transition.
    @Test @MainActor func summaryIsDiscardedWhenTheBodyFails() async {
        let manager = JobManager()
        manager.start(kind: .prune) { context in
            context.reportSummary("stale summary")
            throw TartClientError.commandFailed(command: "prune", exitCode: 1,
                                                stdout: "", stderr: "boom")
        }
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .failed)
        #expect(manager.jobs.first?.summary == nil)
    }

    /// finding 7: the cap is enforced inside reportSummary, for every job
    /// body — not by call-site discipline.
    @Test @MainActor func summaryIsCappedAtPresentationSize() async {
        let manager = JobManager()
        manager.start(kind: .prune) { context in
            context.reportSummary(String(repeating: "x", count: 1_000))
        }
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .completed)
        #expect(manager.jobs.first?.summary?.count == JobInfo.summaryMaxLength)
    }

    /// finding 3 (ordering): the summary is attached in the same mutation
    /// as the terminal phase, before onStateChange observers run.
    @Test @MainActor func summaryIsAttachedBeforeStateChangeObserversRun() async {
        let manager = JobManager()
        var observedSummary: String?
        manager.onStateChange = { job in
            if job.phase == .completed { observedSummary = job.summary }
        }
        manager.start(kind: .prune) { context in
            context.reportSummary("Prune complete — freed 2.0 GB")
        }
        await manager.awaitIdle(timeout: 2)
        #expect(observedSummary == "Prune complete — freed 2.0 GB")
    }
}

/// Minimal async latch for tests.
final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var _isOpen = false

    var isOpen: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isOpen
    }

    func open() {
        lock.lock()
        _isOpen = true
        lock.unlock()
    }
}
