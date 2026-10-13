import Foundation
import Testing
@testable import TartKit

@MainActor
@Suite struct CachePruneCoordinatorTests {
    private func settings() -> AppSettings {
        let defaults = UserDefaults(suiteName: "CachePruneCoordinatorTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.storagePath = "/tmp/cache-prune-home"
        return settings
    }

    private func client(_ binary: String, home: String = "/tmp/cache-prune-home") -> TartClient {
        TartClient(binaryPath: binary, environment: ["TART_HOME": home])
    }

    @Test func automaticPruneStartsOnceAndUsesSavedAge() async throws {
        let settings = settings()
        settings.cachePrunePolicy = .sevenDays
        let (stub, invocation) = StubBinary.makeRecordingStub()
        let client = client(stub)
        let jobs = JobManager()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let coordinator = CachePruneCoordinator(settings: settings, jobManager: jobs,
                                                makeClient: { client }, isStorageAvailable: { true },
                                                now: { now })
        coordinator.startAutomaticPruning()
        coordinator.startAutomaticPruning()
        coordinator.checkAutomaticPruning()
        await jobs.awaitIdle(timeout: 2)
        #expect(jobs.jobs.count == 1)
        #expect(jobs.jobs.first?.phase == .completed)
        #expect(settings.lastAutomaticPruneAttempt(forStoragePath: "/tmp/cache-prune-home") == now)
        #expect(try String(contentsOfFile: invocation, encoding: .utf8) ==
                "prune --entries caches --older-than 7\n")
        coordinator.checkAutomaticPruning()
        #expect(jobs.jobs.count == 1)
    }

    @Test func manualDisablesAutomaticButStillStartsExplicitCleanup() async throws {
        let settings = settings()
        settings.cachePrunePolicy = .manual
        let (stub, invocation) = StubBinary.makeRecordingStub()
        let client = client(stub)
        let jobs = JobManager()
        let coordinator = CachePruneCoordinator(settings: settings, jobManager: jobs,
                                                makeClient: { client }, isStorageAvailable: { true })
        coordinator.startAutomaticPruning()
        coordinator.checkAutomaticPruning()
        #expect(jobs.jobs.isEmpty)
        coordinator.startManualPruning(policy: .manual)
        await jobs.awaitIdle(timeout: 2)
        #expect(jobs.jobs.first?.phase == .completed)
        #expect(try String(contentsOfFile: invocation, encoding: .utf8) ==
                "prune --entries caches --older-than 0\n")
        #expect(settings.lastAutomaticPruneAttempt(forStoragePath: "/tmp/cache-prune-home") == nil)
    }

    @Test func readinessDeferralsDoNotConsumeAttempt() async {
        let settings = settings()
        let jobs = JobManager()
        let client = client(StubBinary.make(script: "#!/bin/sh\nexit 0\n"))
        var storageAvailable = false
        var clientAvailable = false
        let coordinator = CachePruneCoordinator(settings: settings, jobManager: jobs,
                                                makeClient: { clientAvailable ? client : nil },
                                                isStorageAvailable: { storageAvailable })
        coordinator.startAutomaticPruning()
        #expect(jobs.jobs.isEmpty)
        storageAvailable = true
        coordinator.checkAutomaticPruning()
        #expect(jobs.jobs.isEmpty)
        #expect(settings.lastAutomaticPruneAttempt(forStoragePath: "/tmp/cache-prune-home") == nil)
        clientAvailable = true
        coordinator.checkAutomaticPruning()
        await jobs.awaitIdle(timeout: 2)
        #expect(jobs.jobs.count == 1)
    }

    @Test func activeJobsDeferAutomaticPruneUntilIdle() async {
        let settings = settings()
        let jobs = JobManager()
        let gate = AsyncGate()
        jobs.start(kind: .clone(name: "busy-vm", source: "image")) { _ in
            while !gate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
        }
        let client = client(StubBinary.make(script: "#!/bin/sh\nexit 0\n"))
        let coordinator = CachePruneCoordinator(settings: settings, jobManager: jobs,
                                                makeClient: { client }, isStorageAvailable: { true })
        coordinator.startAutomaticPruning()
        #expect(jobs.jobs.count == 1)
        #expect(settings.lastAutomaticPruneAttempt(forStoragePath: "/tmp/cache-prune-home") == nil)
        gate.open()
        await jobs.awaitIdle(timeout: 2)
        coordinator.checkAutomaticPruning()
        await jobs.awaitIdle(timeout: 2)
        #expect(jobs.jobs.count == 2)
        #expect(jobs.jobs.last?.kind == .prune)
    }

    @Test func failureConsumesAttemptAndRetriesOnlyNextDay() async {
        let settings = settings()
        let jobs = JobManager()
        let client = client(StubBinary.make(script: "#!/bin/sh\necho 'permission denied' 1>&2\nexit 7\n"))
        var now = Date(timeIntervalSince1970: 1_000_000)
        let coordinator = CachePruneCoordinator(settings: settings, jobManager: jobs,
                                                makeClient: { client }, isStorageAvailable: { true },
                                                now: { now })
        coordinator.startAutomaticPruning()
        await jobs.awaitIdle(timeout: 2)
        #expect(jobs.jobs.first?.phase == .failed)
        #expect(jobs.jobs.first?.error?.operation == "prune")
        coordinator.checkAutomaticPruning()
        #expect(jobs.jobs.count == 1)
        now = now.addingTimeInterval(86_400)
        coordinator.checkAutomaticPruning()
        await jobs.awaitIdle(timeout: 2)
        #expect(jobs.jobs.count == 2)
    }

    @Test func missingOrMismatchedHomeRefusesBeforeJobStart() {
        let settings = settings()
        for environment in [[:], ["TART_HOME": "/tmp/other-home"], ["TART_HOME": "relative"]] {
            let jobs = JobManager()
            let client = TartClient(binaryPath: "/nonexistent/tart", environment: environment)
            let coordinator = CachePruneCoordinator(settings: settings, jobManager: jobs,
                                                    makeClient: { client }, isStorageAvailable: { true })
            var refusal: TartOperationError?
            coordinator.onRefusal = { refusal = $0 }
            coordinator.startAutomaticPruning()
            #expect(jobs.jobs.isEmpty)
            #expect(settings.lastAutomaticPruneAttempt(forStoragePath: "/tmp/cache-prune-home") == nil)
            coordinator.startManualPruning(policy: .manual)
            #expect(jobs.jobs.isEmpty)
            #expect(refusal?.operation == "prune")
        }
    }

    @Test func duplicateManualPruneIsVisibleAndDoesNotStartSecondJob() async {
        let settings = settings()
        let jobs = JobManager()
        let gate = AsyncGate()
        jobs.start(kind: .prune) { _ in
            while !gate.isOpen { Thread.sleep(forTimeInterval: 0.01) }
        }
        let client = client(StubBinary.make(script: "#!/bin/sh\nexit 0\n"))
        let coordinator = CachePruneCoordinator(settings: settings, jobManager: jobs,
                                                makeClient: { client }, isStorageAvailable: { true })
        var refusal: TartOperationError?
        coordinator.onRefusal = { refusal = $0 }
        coordinator.startManualPruning(policy: .manual)
        #expect(jobs.jobs.count == 1)
        #expect(refusal?.operation == "prune")
        #expect(settings.lastAutomaticPruneAttempt(forStoragePath: "/tmp/cache-prune-home") == nil)
        gate.open()
        await jobs.awaitIdle(timeout: 2)
    }

    @Test func automaticTimerDoesNotRetainCoordinator() {
        let settings = settings()
        settings.cachePrunePolicy = .manual
        let jobs = JobManager()
        var coordinator: CachePruneCoordinator? = CachePruneCoordinator(
            settings: settings, jobManager: jobs, makeClient: { nil }, isStorageAvailable: { false })
        weak let weakCoordinator = coordinator
        coordinator?.startAutomaticPruning()
        coordinator = nil
        #expect(weakCoordinator == nil)
    }
}
