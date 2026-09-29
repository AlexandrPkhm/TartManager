import Testing
import Foundation
@testable import TartKit

@Suite struct SuspendCoordinatorTests {
    func entry(_ name: String, running: Bool = true, guestOS: String? = "darwin") -> VMEntry {
        VMEntry(name: name, source: "local", running: running,
                state: running ? "running" : "stopped",
                diskSize: 0, diskUsage: 0, accessed: nil, guestOS: guestOS)
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
    @Test func suspendReturnsSuspendedAndClearsReservation() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        """)
        let coordinator = SuspendCoordinator()
        let outcome = await coordinator.suspend(
            vm: entry("vm-a"),
            using: TartClient(binaryPath: stub),
            inventory: inventory(fetch: { [] }))
        #expect(outcome == .suspended)
        #expect(coordinator.suspending.isEmpty)
        let line = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "suspend vm-a")
    }

    @MainActor
    @Test func doubleSuspendOfTheSameVMIssuesOnlyOneCommand() async throws {
        // Deterministic variant of the plan's sleep-race test: the stub
        // blocks until a release file appears, so the second click is
        // issued while the first command is provably in flight — immune to
        // task-scheduling jitter under parallel test load.
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
        let coordinator = SuspendCoordinator()
        async let first = coordinator.suspend(vm: entry("vm-a"), using: client, inventory: service)
        // Yield until the first command's argv is recorded: the name is
        // reserved and the command is running.
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: invocationFile),
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let second = await coordinator.suspend(vm: entry("vm-a"), using: client, inventory: service)
        #expect(second == .alreadySuspending(name: "vm-a"))
        // Release the stub so the first suspend can complete.
        try "x".write(toFile: releaseFile, atomically: true, encoding: .utf8)
        let firstOutcome = await first
        #expect(firstOutcome == .suspended)
        #expect(coordinator.suspending.isEmpty)
        let lines = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 1)
    }

    @MainActor
    @Test func failedSuspendWithConfirmedStillRunningIsAnErrorWithTheHint() async {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'not suspendable' 1>&2\nexit 6\n")
        let coordinator = SuspendCoordinator()
        let outcome = await coordinator.suspend(
            vm: entry("vm-a"),
            using: TartClient(binaryPath: stub),
            inventory: inventory(fetch: { [entry("vm-a")] }))
        guard case .stillRunning(_, let error) = outcome else {
            Issue.record("expected .stillRunning, got \(outcome)")
            return
        }
        #expect(error.message.contains("not suspendable"))
        // AC 3's explanation flows through the analyzer into the sheet.
        #expect(error.hint?.contains("suspendable") == true)
    }

    @MainActor
    @Test func failedSuspendReconcilesWhenRefreshShowsNotRunning() async {
        // The refresh reports suspended/stopped — the suspend won the race
        // or the VM stopped anyway: no error.
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'not running' 1>&2\nexit 6\n")
        let coordinator = SuspendCoordinator()
        let outcome = await coordinator.suspend(
            vm: entry("vm-a"),
            using: TartClient(binaryPath: stub),
            inventory: inventory(fetch: { [entry("vm-a", running: false)] }))
        #expect(outcome == .reconciled(name: "vm-a"))
    }

    @MainActor
    @Test func failedSuspendIsUnknownWhenRefreshFailsAndNeverAnError() async {
        // A failed post-suspend refresh must not masquerade as "not
        // running" — the outcome is unknown and the alert is suppressed.
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'VM busy' 1>&2\nexit 6\n")
        let coordinator = SuspendCoordinator()
        let outcome = await coordinator.suspend(
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
        let coordinator = SuspendCoordinator()
        #expect(await coordinator.suspend(vm: entry("vm-a", running: false),
                                           using: TartClient(binaryPath: stub),
                                           inventory: service) == .notSuspendable(name: "vm-a"))
        let oci = VMEntry(name: "img:1", source: "oci", running: false, state: "stopped",
                          diskSize: 0, diskUsage: 0, accessed: nil)
        #expect(await coordinator.suspend(vm: oci,
                                           using: TartClient(binaryPath: stub),
                                           inventory: service) == .notSuspendable(name: "img:1"))
    }

    /// Linux guests cannot be suspended by tart at all: the guard refuses
    /// before any CLI call, so no command can fail with the OS refusal.
    @MainActor
    @Test func skipsLinuxGuestsEvenWhenRunning() async {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: "#!/bin/sh\necho \"$@\" >> \"\(invocationFile)\"\n")
        let coordinator = SuspendCoordinator()
        let linux = entry("vm-a", guestOS: "linux")
        let outcome = await coordinator.suspend(
            vm: linux,
            using: TartClient(binaryPath: stub),
            inventory: inventory(fetch: { [linux] }))
        #expect(outcome == .notSuspendable(name: "vm-a"))
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }
}
