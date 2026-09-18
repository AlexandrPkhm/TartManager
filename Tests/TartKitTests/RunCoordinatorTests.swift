import Testing
import Foundation
@testable import TartKit

@Suite struct RunCoordinatorTests {
    func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir
    }

    func entry(_ name: String, running: Bool) -> VMEntry {
        VMEntry(name: name, source: "local", running: running,
                state: running ? "running" : "stopped",
                diskSize: 0, diskUsage: 0, accessed: nil)
    }

    func client(script: String) -> TartClient {
        TartClient(binaryPath: StubBinary.make(script: script))
    }

    @MainActor
    @Test func concurrentLaunchesOfSameNameSpawnOnlyOneProcess() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocations.txt").path
        let client = client(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        sleep 30
        """)
        let coordinator = RunCoordinator()
        async let first = coordinator.launch(
            name: "vm-a", using: client, earlyFailureWindow: 0.2, logDirectory: dir)
        try await Task.sleep(for: .milliseconds(50)) // second click lands mid-flight
        let second = await coordinator.launch(
            name: "vm-a", using: client, earlyFailureWindow: 0.2, logDirectory: dir)
        let firstOutcome = await first
        guard case .started(let handle) = firstOutcome else {
            Issue.record("expected .started, got \(firstOutcome)")
            return
        }
        defer {
            handle.process.terminate()
            handle.process.waitUntilExit()
        }
        guard case .alreadyLaunching = second else {
            Issue.record("expected .alreadyLaunching, got \(second)")
            return
        }
        // The stub needs a moment to be scheduled and write its capture;
        // poll instead of racing the read.
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: invocationFile),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let lines = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 1)
        #expect(lines.first == "run --suspendable vm-a")
    }

    @MainActor
    @Test func failedLaunchReleasesReservation() async {
        let dir = tempDir()
        let bad = client(script: "#!/bin/sh\necho boom 1>&2\nexit 7\n")
        let coordinator = RunCoordinator()
        let first = await coordinator.launch(
            name: "vm-a", using: bad, earlyFailureWindow: 3.0, logDirectory: dir)
        guard case .failed = first else {
            Issue.record("expected .failed, got \(first)")
            return
        }
        // Reservation must be gone: a retry reaches tart again instead of
        // getting .alreadyLaunching.
        let second = await coordinator.launch(
            name: "vm-a", using: bad, earlyFailureWindow: 3.0, logDirectory: dir)
        guard case .failed = second else {
            Issue.record("expected .failed on retry (reservation released), got \(second)")
            return
        }
    }

    @MainActor
    @Test func reconcileEvictsVMStoppedPerInventoryAllowingRerun() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocations.txt").path
        let client = client(script: """
        #!/bin/sh
        echo "$1 $2" >> "\(invocationFile)"
        sleep 30
        """)
        let coordinator = RunCoordinator()
        let firstOutcome = await coordinator.launch(
            name: "vm-a", using: client, earlyFailureWindow: 0.2, logDirectory: dir)
        guard case .started(let first) = firstOutcome else {
            Issue.record("expected .started, got \(firstOutcome)")
            return
        }
        #expect(coordinator.isRegistered("vm-a"))
        // The poll reports the VM stopped (window closed / tart stop):
        // the registry must evict it so a later Run works again.
        coordinator.reconcile(with: [entry("vm-a", running: false)])
        #expect(!coordinator.isRegistered("vm-a"))
        let secondOutcome = await coordinator.launch(
            name: "vm-a", using: client, earlyFailureWindow: 0.2, logDirectory: dir)
        guard case .started(let second) = secondOutcome else {
            Issue.record("expected .started after eviction, got \(secondOutcome)")
            first.process.terminate(); first.process.waitUntilExit()
            return
        }
        defer {
            first.process.terminate(); first.process.waitUntilExit()
            second.process.terminate(); second.process.waitUntilExit()
        }
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: invocationFile),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let lines = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 2) // run → stop → run spawns again
    }

    @MainActor
    @Test func reconcileEvictsExitedHandle() async throws {
        let dir = tempDir()
        let client = client(script: "#!/bin/sh\nsleep 0.4\n")
        let coordinator = RunCoordinator()
        let outcome = await coordinator.launch(
            name: "vm-a", using: client, earlyFailureWindow: 0.2, logDirectory: dir)
        guard case .started(let handle) = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        // Wait for the stub to exit on its own (window 0.2 < sleep 0.4).
        for _ in 0..<40 where handle.isRunning {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!handle.isRunning)
        coordinator.reconcile(with: [entry("vm-a", running: true)])
        #expect(!coordinator.isRegistered("vm-a")) // evicted because the child exited
    }

    @MainActor
    @Test func failureOutcomeCarriesUserFacingMessageWithStderr() async {
        let dir = tempDir()
        let bad = client(script: "#!/bin/sh\necho 'no such VM' 1>&2\nexit 12\n")
        let coordinator = RunCoordinator()
        let outcome = await coordinator.launch(
            name: "ghost", using: bad, earlyFailureWindow: 3.0, logDirectory: dir)
        guard case .failed(_, let message, let cause) = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        #expect(message.contains("Couldn't run ghost"))
        #expect(message.contains("no such VM"))
        // The raw client failure rides along for the standardized report.
        guard case .commandFailed(_, let exitCode, _, let stderr) = cause else {
            Issue.record("expected a commandFailed cause, got \(cause)")
            return
        }
        #expect(exitCode == 12)
        #expect(stderr.contains("no such VM"))
    }

    @MainActor
    @Test func cleanupStaleLogsRemovesOnlyRunLogs() throws {
        let dir = tempDir()
        let staleA = dir.appendingPathComponent("tartmanager-run-AAA.log")
        let staleB = dir.appendingPathComponent("tartmanager-run-BBB.log")
        let keep = dir.appendingPathComponent("tartmanager-tests-keep.log")
        try "x".write(to: staleA, atomically: true, encoding: .utf8)
        try "y".write(to: staleB, atomically: true, encoding: .utf8)
        try "z".write(to: keep, atomically: true, encoding: .utf8)
        RunCoordinator.cleanupStaleLogs(in: dir)
        #expect(!FileManager.default.fileExists(atPath: staleA.path))
        #expect(!FileManager.default.fileExists(atPath: staleB.path))
        #expect(FileManager.default.fileExists(atPath: keep.path))
    }

    @MainActor
    @Test func releaseEvictsRegisteredHandleSoResumeIsNeverBlocked() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocations.txt").path
        let client = client(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        sleep 30
        """)
        let coordinator = RunCoordinator()
        let firstOutcome = await coordinator.launch(
            name: "vm-a", using: client, earlyFailureWindow: 0.2, logDirectory: dir)
        guard case .started(let first) = firstOutcome else {
            Issue.record("expected .started, got \(firstOutcome)")
            return
        }
        #expect(coordinator.isRegistered("vm-a"))
        // Suspend removes the VM from running: its run handle is stale.
        // Release must evict it immediately (no poll dependency), so the
        // Resume click — the same launch path — is accepted and issues the
        // same `tart run --suspendable` argv that resumes the session.
        coordinator.release(name: "vm-a")
        #expect(!coordinator.isRegistered("vm-a"))
        let resumeOutcome = await coordinator.launch(
            name: "vm-a", using: client, earlyFailureWindow: 0.2, logDirectory: dir)
        guard case .started(let second) = resumeOutcome else {
            Issue.record("expected .started on resume, got \(resumeOutcome)")
            first.process.terminate(); first.process.waitUntilExit()
            return
        }
        defer {
            first.process.terminate(); first.process.waitUntilExit()
            second.process.terminate(); second.process.waitUntilExit()
        }
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: invocationFile),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let lines = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 2) // run → suspend (release) → resume runs again
        #expect(lines.allSatisfy { String($0) == "run --suspendable vm-a" })
    }

    @MainActor
    @Test func releaseOfUnregisteredNameIsANoOp() {
        let coordinator = RunCoordinator()
        coordinator.release(name: "ghost")
        #expect(!coordinator.isRegistered("ghost"))
    }
}
