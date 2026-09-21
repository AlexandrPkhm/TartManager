import Testing
import Foundation
@testable import TartKit

@Suite @MainActor struct ClipboardWatchdogCoordinatorTests {
    func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir
    }

    private let darwinConfig =
        #"{"OS":"darwin","CPU":4,"Memory":8192,"Disk":40,"DiskFormat":"raw","Size":"27.123","Display":"1024x768"}"#
    private let linuxConfig =
        #"{"OS":"linux","CPU":4,"Memory":2048,"Disk":20,"DiskFormat":"raw","Size":"7.123","Display":"1024x768"}"#

    private func fastConfiguration() -> ClipboardWatchdogCoordinator.Configuration {
        ClipboardWatchdogCoordinator.Configuration(readinessTimeout: 2, recheckTimeout: 1, pollInterval: 0.05)
    }

    @Test func waitsForReadinessThenKicksAndInstallsForADarwinGuest() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        case "$1" in
          get) printf '%s\\n' '\(darwinConfig)' ;;
          exec) echo "$@" >> "\(invocationFile)"; printf 'ready\\n' ;;
          *) exit 0 ;;
        esac
        """)
        let client = TartClient(binaryPath: stub)
        let coordinator = ClipboardWatchdogCoordinator(configuration: fastConfiguration())
        await coordinator.ensureInstalled(name: "vm-a", client: client)
        let text = try String(contentsOfFile: invocationFile, encoding: .utf8)
        #expect(text.contains("exec vm-a sh -lc echo ready"))
        #expect(text.contains("launchctl kickstart -k gui/$(id -u)/org.cirruslabs.tart-guest-agent"))
        // The installer bootstraps by plist path (2-arg form): the label
        // travels inside the plist, not in the domain path.
        #expect(text.contains("launchctl bootstrap gui/$(id -u)"))
        // Readiness is probed both before the kick and after it.
        #expect(text.components(separatedBy: "echo ready").count - 1 >= 2)
    }

    @Test func skipsNonDarwinGuestsBeforeRunningAnyGuestCommand() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        case "$1" in
          get) printf '%s\\n' '\(linuxConfig)' ;;
          exec) echo "$@" >> "\(invocationFile)"; printf 'ready\\n' ;;
          *) exit 0 ;;
        esac
        """)
        let client = TartClient(binaryPath: stub)
        let coordinator = ClipboardWatchdogCoordinator(configuration: fastConfiguration())
        await coordinator.ensureInstalled(name: "vm-a", client: client)
        // No guest command ran at all: launchd does not exist in Linux guests.
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }

    @Test func degradesWithoutThrowingWhenTheAgentNeverAnswers() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        case "$1" in
          get) printf '%s\\n' '\(darwinConfig)' ;;
          exec) echo "$@" >> "\(invocationFile)"; echo 'agent is not running' 1>&2; exit 1 ;;
          *) exit 0 ;;
        esac
        """)
        let client = TartClient(binaryPath: stub)
        let coordinator = ClipboardWatchdogCoordinator(configuration: fastConfiguration())
        await coordinator.ensureInstalled(name: "vm-a", client: client)
        // Only probes ran; no kickstart, no install, and no thrown error.
        let text = try String(contentsOfFile: invocationFile, encoding: .utf8)
        #expect(!text.contains("kickstart"))
        #expect(!text.contains("bootstrap"))
    }

    @Test func concurrentEnsureForTheSameVMIssuesOnlyOneInstall() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let releaseFile = dir.appendingPathComponent("release.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        case "$1" in
          get) while [ ! -f "\(releaseFile)" ]; do sleep 0.05; done; printf '%s\\n' '\(darwinConfig)' ;;
          exec) echo "$@" >> "\(invocationFile)"; printf 'ready\\n' ;;
          *) exit 0 ;;
        esac
        """)
        let client = TartClient(binaryPath: stub)
        let coordinator = ClipboardWatchdogCoordinator(configuration: fastConfiguration())
        async let first: Void = coordinator.ensureInstalled(name: "vm-a", client: client)
        async let second: Void = coordinator.ensureInstalled(name: "vm-a", client: client)
        // Let the first call reserve the name and suspend at its gated `get`;
        // the second call must then no-op on the synchronous reservation.
        try? await Task.sleep(for: .milliseconds(200))
        try "".write(toFile: releaseFile, atomically: true, encoding: .utf8)
        await first
        await second
        let text = try String(contentsOfFile: invocationFile, encoding: .utf8)
        #expect(text.components(separatedBy: "launchctl bootstrap").count == 2) // exactly one install
    }
}
