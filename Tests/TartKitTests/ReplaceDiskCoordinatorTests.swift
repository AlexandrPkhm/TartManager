import Testing
import Foundation
@testable import TartKit

@MainActor
@Suite struct ReplaceDiskCoordinatorTests {
    func entry(_ name: String = "vm-a", source: String = "local",
               running: Bool = false, state: String = "stopped") -> VMEntry {
        VMEntry(name: name, source: source, running: running, state: state,
                diskSize: 80, diskUsage: 75, accessed: nil)
    }

    /// A stub that would write its argv to a marker file **if spawned**.
    func markerStub() -> (stub: String, marker: String) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        let marker = dir.appendingPathComponent("spawned.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" > "\(marker)"
        """)
        return (stub, marker)
    }

    func notSpawned(_ marker: String) -> Bool {
        !FileManager.default.fileExists(atPath: marker)
    }

    @Test func gateFailureIsRefusedBeforeAnySpawn() {
        // The issue's automated check "cancel-at-gate making no call": a gate
        // that has not passed is the only state a cancelled sheet reaches,
        // and it must never spawn tart.
        let (stub, marker) = markerStub()
        let coordinator = ReplaceDiskCoordinator()
        let outcome = coordinator.start(vm: entry(), typedName: "VM-A",
                                        path: "/images/clean.img",
                                        using: TartClient(binaryPath: stub),
                                        jobManager: JobManager())
        #expect(outcome == .refused(reason: .gateFailed))
        #expect(notSpawned(marker))
    }

    @Test func runningVMIsRefusedBeforeAnySpawn() {
        let (stub, marker) = markerStub()
        let coordinator = ReplaceDiskCoordinator()
        let outcome = coordinator.start(vm: entry(running: true, state: "running"),
                                        typedName: "vm-a", path: "/images/clean.img",
                                        using: TartClient(binaryPath: stub),
                                        jobManager: JobManager())
        #expect(outcome == .refused(reason: .running))
        #expect(notSpawned(marker))
    }

    @Test func suspendedVMIsRefusedBeforeAnySpawn() {
        // Finding 1: suspended is its own tested refusal — never a silent
        // no-op after the confirmation gates.
        let (stub, marker) = markerStub()
        let coordinator = ReplaceDiskCoordinator()
        let outcome = coordinator.start(vm: entry(state: "suspended"),
                                        typedName: "vm-a", path: "/images/clean.img",
                                        using: TartClient(binaryPath: stub),
                                        jobManager: JobManager())
        #expect(outcome == .refused(reason: .suspended))
        #expect(notSpawned(marker))
    }

    @Test func ociEntryIsRefusedBeforeAnySpawn() {
        let (stub, marker) = markerStub()
        let coordinator = ReplaceDiskCoordinator()
        let outcome = coordinator.start(vm: entry(source: "OCI"),
                                        typedName: "vm-a", path: "/images/clean.img",
                                        using: TartClient(binaryPath: stub),
                                        jobManager: JobManager())
        #expect(outcome == .refused(reason: .notLocal))
        #expect(notSpawned(marker))
    }

    @Test func validStoppedLocalVMStartsAJobEndToEnd() async throws {
        let (stub, marker) = markerStub()
        let manager = JobManager()
        let coordinator = ReplaceDiskCoordinator()
        let outcome = coordinator.start(vm: entry(), typedName: "vm-a",
                                        path: "/images/clean.img",
                                        using: TartClient(binaryPath: stub),
                                        jobManager: manager)
        guard case .started(let jobID) = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        #expect(manager.jobs.first?.id == jobID)
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .completed)
        #expect(manager.jobs.first?.progress?.fraction == nil) // indeterminate
        // End-to-end argv proof for the destructive command.
        let line = try String(contentsOfFile: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "set vm-a --disk /images/clean.img")
    }

    @Test func duplicateInFlightTargetIsRefusedVisibly() async {
        // Finding 5: a second replace attempt for the same VM is refused as
        // `.inFlight` (presented), never a silent nil.
        let sleepStub = StubBinary.make(script: "#!/bin/sh\nsleep 1\n")
        let manager = JobManager()
        let coordinator = ReplaceDiskCoordinator()
        let first = coordinator.start(vm: entry(), typedName: "vm-a",
                                      path: "/images/clean.img",
                                      using: TartClient(binaryPath: sleepStub),
                                      jobManager: manager)
        guard case .started = first else {
            Issue.record("expected first start to succeed")
            return
        }
        let second = coordinator.start(vm: entry(), typedName: "vm-a",
                                       path: "/images/clean.img",
                                       using: TartClient(binaryPath: sleepStub),
                                       jobManager: manager)
        #expect(second == .refused(reason: .inFlight))
        await manager.awaitIdle(timeout: 3)
    }
}
