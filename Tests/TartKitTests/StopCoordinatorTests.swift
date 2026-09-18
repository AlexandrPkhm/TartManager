import Testing
import Foundation
@testable import TartKit

@Suite struct StopCoordinatorTests {
    func entry(_ name: String, running: Bool = true) -> VMEntry {
        VMEntry(name: name, source: "local", running: running,
                state: running ? "running" : "stopped",
                diskSize: 0, diskUsage: 0, accessed: nil)
    }

    func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir
    }

    @MainActor
    func inventory(fetch: @escaping () throws -> [VMEntry]) -> InventoryService {
        InventoryService(fetch: fetch, pollInterval: 3600)
    }

    @MainActor
    @Test func gracefulStopReturnsStoppedAndClearsReservation() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        """)
        let coordinator = StopCoordinator()
        let outcome = await coordinator.stop(
            vm: entry("vm-a"),
            using: TartClient(binaryPath: stub),
            inventory: inventory(fetch: { [] }))
        #expect(outcome == .stopped)
        #expect(coordinator.stopping.isEmpty)
        let line = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "stop vm-a")
    }

    @MainActor
    @Test func forceStopPassesZeroTimeoutThroughTheCoordinator() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        """)
        let coordinator = StopCoordinator()
        let outcome = await coordinator.stop(
            vm: entry("vm-a"), force: true,
            using: TartClient(binaryPath: stub),
            inventory: inventory(fetch: { [] }))
        #expect(outcome == .stopped)
        let line = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "stop vm-a --timeout 0")
    }

    @MainActor
    @Test func doubleStopOfTheSameVMIssuesOnlyOneCommand() async throws {
        // Deterministic single-flight proof: the stub blocks until a release
        // file appears, so the second click runs while the first command is
        // provably in flight. The prior fixed-sleep variant raced task
        // scheduling under parallel test load (the sleep overshot the stub's
        // 0.6 s duration, letting the first stop finish first).
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let releaseFile = dir.appendingPathComponent("release.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        while [ ! -f "\(releaseFile)" ]; do sleep 0.05; done
        """)
        let client = TartClient(binaryPath: stub)
        let service = inventory(fetch: { [] })
        let coordinator = StopCoordinator()
        async let first = coordinator.stop(vm: entry("vm-a"), using: client, inventory: service)
        // Yield until the first command's argv is recorded: the name is
        // reserved and the command is running.
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: invocationFile),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let second = await coordinator.stop(vm: entry("vm-a"), using: client, inventory: service)
        #expect(second == .alreadyStopping(name: "vm-a"))
        // Release the stub so the first stop can complete.
        try "x".write(toFile: releaseFile, atomically: true, encoding: .utf8)
        let firstOutcome = await first
        #expect(firstOutcome == .stopped)
        #expect(coordinator.stopping.isEmpty)
        let lines = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 1)
    }

    @MainActor
    @Test func failedStopWithConfirmedStillRunningIsAnError() async {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'VM busy' 1>&2\nexit 9\n")
        let coordinator = StopCoordinator()
        let outcome = await coordinator.stop(
            vm: entry("vm-a"),
            using: TartClient(binaryPath: stub),
            inventory: inventory(fetch: { [entry("vm-a")] }))
        guard case .stillRunning(_, let message, let cause) = outcome else {
            Issue.record("expected .stillRunning, got \(outcome)")
            return
        }
        #expect(message.contains("Couldn't stop vm-a"))
        #expect(message.contains("VM busy"))
        // The raw client failure rides along for the standardized report.
        guard case .commandFailed(_, let exitCode, _, let stderr) = cause else {
            Issue.record("expected a commandFailed cause, got \(cause)")
            return
        }
        #expect(exitCode == 9)
        #expect(stderr.contains("VM busy"))
    }

    @MainActor
    @Test func failedStopReconcilesWhenRefreshShowsStopped() async {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'not running' 1>&2\nexit 9\n")
        let coordinator = StopCoordinator()
        let outcome = await coordinator.stop(
            vm: entry("vm-a"),
            using: TartClient(binaryPath: stub),
            inventory: inventory(fetch: { [entry("vm-a", running: false)] }))
        #expect(outcome == .reconciled(name: "vm-a"))
    }

    @MainActor
    @Test func failedStopIsUnknownWhenRefreshFailsAndNeverAnError() async {
        // A failed post-stop refresh must not masquerade as "not running" —
        // the outcome is unknown and the alert is suppressed.
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'VM busy' 1>&2\nexit 9\n")
        let coordinator = StopCoordinator()
        let outcome = await coordinator.stop(
            vm: entry("vm-a"),
            using: TartClient(binaryPath: stub),
            inventory: inventory(fetch: { throw InventoryFetchError.unavailable }))
        guard case .unknown = outcome else {
            Issue.record("expected .unknown (suppressed), got \(outcome)")
            return
        }
    }

    @MainActor
    @Test func skipsEntriesThatAreNotRunningLocalVMs() async {
        let stub = StubBinary.make(script: "#!/bin/sh\n# must never be invoked\n")
        let service = inventory(fetch: { [] })
        let coordinator = StopCoordinator()
        #expect(await coordinator.stop(vm: entry("vm-a", running: false),
                                       using: TartClient(binaryPath: stub),
                                       inventory: service) == .notStoppable(name: "vm-a"))
        let oci = VMEntry(name: "img:1", source: "oci", running: false, state: "stopped",
                          diskSize: 0, diskUsage: 0, accessed: nil)
        #expect(await coordinator.stop(vm: oci,
                                       using: TartClient(binaryPath: stub),
                                       inventory: service) == .notStoppable(name: "img:1"))
    }
}
