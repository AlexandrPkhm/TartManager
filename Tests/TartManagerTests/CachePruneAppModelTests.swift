import Testing
import Foundation
import Combine
@testable import TartKit
@testable import TartManager

@Suite @MainActor struct CachePruneAppModelTests {
    @Test func savedManualPolicyDisablesReclamationForEveryClient() throws {
        let defaults = UserDefaults(suiteName: "CachePruneAppModelTests-\(UUID().uuidString)")!
        // Zero is the persisted Manual choice; restore it as an app relaunch would.
        defaults.set(0, forKey: "pruneRetentionDays")
        let settings = AppSettings(defaults: defaults)
        settings.storagePath = "/tmp/manual-vm-storage"
        let model = AppModel(settings: settings)
        model.prerequisite = .ok(version: TartVersion(major: 2, minor: 32, patch: 0),
                                 binaryPath: "/test/tart")

        let client = try #require(model.makeTartClient())
        #expect(client.environment["TART_HOME"] == "/tmp/manual-vm-storage")
        #expect(client.environment["TART_NO_AUTO_PRUNE"] == "1")
        #expect(model.commandEnvironment?.environment["TART_NO_AUTO_PRUNE"] == "1")
    }

    @Test func launchSchedulesOneAgeBasedCleanup() async throws {
        let fixture = try makeFixture(policy: .sevenDays)

        fixture.model.startAutomaticPruning()
        fixture.model.startAutomaticPruning()
        await fixture.model.jobManager.awaitIdle(timeout: 10)

        #expect(fixture.model.jobManager.jobs.count == 1)
        #expect(fixture.model.jobManager.jobs.first?.phase == .completed)
        #expect(try String(contentsOfFile: fixture.invocations, encoding: .utf8)
            == "prune --entries caches --older-than 7\n")
        #expect(fixture.model.settings.lastAutomaticPruneAttempt(
            forStoragePath: fixture.storage.path) != nil)
    }

    @Test func manualPolicySkipsLaunchButButtonPrunesAllCaches() async throws {
        let fixture = try makeFixture(policy: .manual)
        fixture.model.startAutomaticPruning()
        #expect(fixture.model.jobManager.jobs.isEmpty)

        fixture.model.startPrune(policy: .manual)
        await fixture.model.jobManager.awaitIdle(timeout: 10)

        #expect(fixture.model.jobManager.jobs.count == 1)
        #expect(fixture.model.jobManager.jobs.first?.phase == .completed)
        #expect(try String(contentsOfFile: fixture.invocations, encoding: .utf8)
            == "prune --entries caches --older-than 0\n")
        #expect(fixture.model.settings.lastAutomaticPruneAttempt(
            forStoragePath: fixture.storage.path) == nil)
    }

    @Test func automaticCleanupWaitsForTartReadiness() async throws {
        let fixture = try makeFixture(policy: .thirtyDays)
        let prerequisite = fixture.model.prerequisite
        fixture.model.prerequisite = nil
        fixture.model.startAutomaticPruning()
        #expect(fixture.model.jobManager.jobs.isEmpty)
        #expect(fixture.model.settings.lastAutomaticPruneAttempt(
            forStoragePath: fixture.storage.path) == nil)

        fixture.model.prerequisite = prerequisite
        fixture.model.checkAutomaticPruning()
        await fixture.model.jobManager.awaitIdle(timeout: 10)

        #expect(fixture.model.jobManager.jobs.count == 1)
        #expect(try String(contentsOfFile: fixture.invocations, encoding: .utf8)
            == "prune --entries caches --older-than 30\n")
    }

    @Test func choosingManualImmediatelyUpdatesAllCommandEnvironments() throws {
        let fixture = try makeFixture(policy: .fourteenDays)

        fixture.model.setCachePrunePolicy(.manual)
        #expect(fixture.model.settings.cachePrunePolicy == .manual)
        #expect(fixture.model.commandEnvironment?.environment["TART_NO_AUTO_PRUNE"] == "1")
        #expect(fixture.model.makeTartClient()?.environment["TART_NO_AUTO_PRUNE"] == "1")

        fixture.model.setCachePrunePolicy(.fourteenDays)
        #expect(fixture.model.commandEnvironment?.environment["TART_NO_AUTO_PRUNE"] == nil)
        #expect(fixture.model.makeTartClient()?.environment["TART_NO_AUTO_PRUNE"] == nil)
    }

    @Test func choosingManualNotifiesTheSettingsView() throws {
        let fixture = try makeFixture(policy: .fourteenDays)
        var notified = false
        let observation = fixture.model.objectWillChange.sink { notified = true }
        defer { observation.cancel() }

        fixture.model.setCachePrunePolicy(.manual)

        #expect(notified)
        #expect(fixture.model.settings.cachePrunePolicy == .manual)
    }

    @Test func manualCleanupRefusalIsPresentedThroughExistingErrorReport() throws {
        let fixture = try makeFixture(policy: .manual)
        fixture.model.prerequisite = nil

        fixture.model.startPrune(policy: .manual)

        #expect(fixture.model.jobManager.jobs.isEmpty)
        #expect(fixture.model.activeError?.operation == "prune")
        #expect(fixture.model.activeError?.message.contains("tart is unavailable") == true)
    }

    @Test func automaticCleanupResumesWhenOtherJobsFinish() async throws {
        let fixture = try makeFixture(policy: .sevenDays)
        let release = DispatchSemaphore(value: 0)
        fixture.model.jobManager.start(kind: .clone(name: "busy-vm", source: "image")) { _ in
            release.wait()
        }
        fixture.model.startAutomaticPruning()
        #expect(fixture.model.jobManager.jobs.count == 1)
        #expect(fixture.model.settings.lastAutomaticPruneAttempt(
            forStoragePath: fixture.storage.path) == nil)

        release.signal()
        await fixture.model.jobManager.awaitIdle(timeout: 10)

        #expect(fixture.model.jobManager.jobs.count == 2)
        #expect(fixture.model.jobManager.jobs.last?.kind == .prune)
        #expect(fixture.model.jobManager.jobs.last?.phase == .completed)
    }

    @Test func choosingManualStopsDeferredAutomaticCleanup() async throws {
        let fixture = try makeFixture(policy: .fourteenDays)
        let release = DispatchSemaphore(value: 0)
        fixture.model.jobManager.start(kind: .clone(name: "busy-vm", source: "image")) { _ in
            release.wait()
        }
        fixture.model.startAutomaticPruning()
        fixture.model.setCachePrunePolicy(.manual)

        release.signal()
        await fixture.model.jobManager.awaitIdle(timeout: 10)

        #expect(fixture.model.jobManager.jobs.count == 1)
        #expect(fixture.model.settings.lastAutomaticPruneAttempt(
            forStoragePath: fixture.storage.path) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.invocations))
    }

    private func makeFixture(policy: CachePrunePolicy) throws
        -> (model: AppModel, storage: URL, invocations: String) {
        let storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-prune-app-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let invocations = storage.appendingPathComponent("invocations.txt").path
        let binary = storage.appendingPathComponent("tart").path
        let script = """
        #!/bin/sh
        if [ "$1" = "prune" ]; then
          printf '%s\\n' "$*" >> "\(invocations)"
        elif [ "$1" = "list" ]; then
          printf '[]'
        fi
        exit 0
        """
        try script.write(toFile: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)
        let defaults = UserDefaults(suiteName: "CachePruneAppModelTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        settings.storagePath = storage.path
        settings.cachePrunePolicy = policy
        let model = AppModel(settings: settings)
        model.prerequisite = .ok(version: TartVersion(major: 2, minor: 32, patch: 0),
                                 binaryPath: binary)
        model.inventoryService.updateFetch { [] }
        return (model, storage, invocations)
    }
}
