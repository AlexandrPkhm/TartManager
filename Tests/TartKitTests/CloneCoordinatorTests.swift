import Testing
import Foundation
@testable import TartKit

@MainActor
@Suite struct CloneCoordinatorTests {
    func entry(_ name: String = "golden-vm", source: String = "local",
               running: Bool = false) -> VMEntry {
        VMEntry(name: name, source: source, running: running,
                state: running ? "running" : "stopped",
                diskSize: 50, diskUsage: 50, accessed: nil)
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

    @Test func runningSourceIsRefusedBeforeAnySpawn() {
        // The issue's mandated automated check: a running source produces a
        // refusal and **no tart subprocess** (marker file never written).
        let (stub, marker) = markerStub()
        let coordinator = CloneCoordinator()
        let outcome = coordinator.start(
            source: entry(running: true), newName: "vm-from-golden", taken: [],
            using: TartClient(binaryPath: stub), jobManager: JobManager())
        #expect(outcome == .refused(reason: .source(.running)))
        #expect(notSpawned(marker))
    }

    @Test func takenNameIsRefusedBeforeAnySpawn() {
        // Uniqueness pre-validation (issue How-to-Verify Automated).
        let (stub, marker) = markerStub()
        let coordinator = CloneCoordinator()
        let outcome = coordinator.start(
            source: entry(), newName: "vm-from-golden", taken: ["vm-from-golden"],
            using: TartClient(binaryPath: stub), jobManager: JobManager())
        #expect(outcome == .refused(reason: .name(.taken)))
        #expect(notSpawned(marker))
    }

    @Test func invalidNameIsRefused() {
        let (stub, marker) = markerStub()
        let coordinator = CloneCoordinator()
        let outcome = coordinator.start(
            source: entry(), newName: "../vm", taken: [],
            using: TartClient(binaryPath: stub), jobManager: JobManager())
        #expect(outcome == .refused(reason: .name(.invalidSyntax)))
        #expect(notSpawned(marker))
    }

    @Test func ociSourceIsRefused() {
        let (stub, marker) = markerStub()
        let coordinator = CloneCoordinator()
        let outcome = coordinator.start(
            source: entry(source: "OCI"), newName: "vm-from-image", taken: [],
            using: TartClient(binaryPath: stub), jobManager: JobManager())
        #expect(outcome == .refused(reason: .source(.notLocal)))
        #expect(notSpawned(marker))
    }

    @Test func validStoppedLocalVMStartsAJobEndToEnd() async throws {
        let (stub, marker) = markerStub()
        let manager = JobManager()
        let coordinator = CloneCoordinator()
        let outcome = coordinator.start(
            source: entry(), newName: "vm-from-golden", taken: [],
            using: TartClient(binaryPath: stub), jobManager: manager)
        guard case .started(let jobID) = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        #expect(manager.jobs.first?.id == jobID)
        await manager.awaitIdle(timeout: 2)
        #expect(manager.jobs.first?.phase == .completed)
        // End-to-end argv proof for the local-source form of the command.
        let line = try String(contentsOfFile: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "clone golden-vm vm-from-golden")
    }

    @Test func duplicateInFlightTargetMapsToTaken() async {
        let sleepStub = StubBinary.make(script: "#!/bin/sh\nsleep 5\n")
        let manager = JobManager()
        let coordinator = CloneCoordinator()
        let first = coordinator.start(source: entry(), newName: "vm-from-golden",
                                      taken: [], using: TartClient(binaryPath: sleepStub),
                                      jobManager: manager)
        guard case .started = first else {
            Issue.record("expected first start to succeed")
            return
        }
        let second = coordinator.start(source: entry(), newName: "vm-from-golden",
                                       taken: [], using: TartClient(binaryPath: sleepStub),
                                       jobManager: manager)
        #expect(second == .refused(reason: .name(.taken)))
        manager.cancel(id: manager.jobs[0].id)
        await manager.awaitIdle(timeout: 3)
    }
}
