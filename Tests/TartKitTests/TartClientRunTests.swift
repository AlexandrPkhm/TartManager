import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientRunTests {
    func isolatedLogDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir
    }

    @Test func runVMPassesSuspendableFlagTartHomeAndName() throws {
        let dir = isolatedLogDirectory()
        let storagePath = VMStorageFixture.make(storageWithVM: "vm-a", os: "darwin")
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$TART_HOME" >> "\(invocationFile)"
        echo "$@" >> "\(invocationFile)"
        sleep 30
        """)
        let client = TartClient(
            binaryPath: stub,
            environment: TartCommandEnvironment(storagePath: storagePath).environment)
        let handle = try client.runVM(
            name: "vm-a", earlyFailureWindow: 0.3, logDirectory: dir)
        defer {
            handle.process.terminate()
            handle.process.waitUntilExit()
        }
        // The stub needs a moment to be scheduled and write its captures;
        // poll instead of racing the read.
        let lines = CaptureFile.waitForLines(atPath: invocationFile, count: 2)
        #expect(lines.contains(storagePath))
        #expect(lines.contains("run --suspendable vm-a"))
    }

    /// The Linux run refusal ("You can only suspend macOS VMs", exit 64):
    /// non-macOS guests launch without the flag tart rejects.
    @Test func runVMOmitsSuspendableFlagForLinuxGuests() throws {
        let dir = isolatedLogDirectory()
        let storagePath = VMStorageFixture.make(storageWithVM: "vm-a", os: "linux")
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        sleep 30
        """)
        let client = TartClient(
            binaryPath: stub,
            environment: TartCommandEnvironment(storagePath: storagePath).environment)
        let handle = try client.runVM(
            name: "vm-a", earlyFailureWindow: 0.3, logDirectory: dir)
        defer {
            handle.process.terminate()
            handle.process.waitUntilExit()
        }
        let lines = CaptureFile.waitForLines(atPath: invocationFile, count: 1)
        #expect(lines.contains("run vm-a"))
        #expect(!lines.contains("run --suspendable vm-a"))
    }

    /// An unreadable config is not known to be macOS: the conservative
    /// default must never reintroduce tart's Linux refusal.
    @Test func runVMWithoutReadableConfigOmitsSuspendableFlag() throws {
        let dir = isolatedLogDirectory()
        let storagePath = VMStorageFixture.make(storageWithVM: "vm-a", os: nil)
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        sleep 30
        """)
        let client = TartClient(
            binaryPath: stub,
            environment: TartCommandEnvironment(storagePath: storagePath).environment)
        let handle = try client.runVM(
            name: "vm-a", earlyFailureWindow: 0.3, logDirectory: dir)
        defer {
            handle.process.terminate()
            handle.process.waitUntilExit()
        }
        let lines = CaptureFile.waitForLines(atPath: invocationFile, count: 1)
        #expect(lines.contains("run vm-a"))
    }

    @Test func vmStoragePathRejectsTraversalNamesEvenWhenTheirTargetExists() throws {
        let storagePath = VMStorageFixture.make(storageWithVM: "vm-a", os: "darwin")
        let escapedDirectory = storagePath + "/escaped"
        try FileManager.default.createDirectory(atPath: escapedDirectory, withIntermediateDirectories: true)
        let environment = TartCommandEnvironment(storagePath: storagePath).environment

        #expect(TartClient.vmStoragePath(environment: environment, name: "vm-a")
            == storagePath + "/vms/vm-a")
        #expect(TartClient.vmStoragePath(environment: environment, name: "../escaped") == nil)
    }

    @Test func quickExitMapsToTartClientError() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'no such VM' 1>&2\nexit 12\n")
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.runVM(name: "ghost", earlyFailureWindow: 3.0,
                                 logDirectory: isolatedLogDirectory())
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, stdout, stderr) {
            #expect(command == "run")
            #expect(exitCode == 12)
            #expect(stderr.contains("no such VM"))
            _ = stdout
        } catch {
            Issue.record("expected commandFailed, got \(error)")
        }
    }

    @Test func earlyFailureWindowDefaultIsSharedConstant() {
        // One named constant, used by both defaults.
        #expect(DetachedLaunchConfiguration.defaultEarlyFailureWindow == 5)
        let config = DetachedLaunchConfiguration(
            binaryPath: "/x", arguments: [], environment: [:])
        #expect(config.earlyFailureWindow == DetachedLaunchConfiguration.defaultEarlyFailureWindow)
    }

    /// Working-directory contract for tart's per-VM control socket: the run
    /// launches from `$TART_HOME/vms/<name>` (spaces intact — the exact
    /// configuration that breaks tart's own chdir) and removes a stale
    /// `control.sock` left by a dead run so the new bind cannot hit a
    /// silent EADDRINUSE.
    @Test func runVMLaunchesFromTheVMDirectoryAndRemovesAStaleControlSocket() throws {
        let dir = isolatedLogDirectory()
        // Storage path with a space — the exact configuration that breaks
        // tart's own percent-encoded control-socket chdir — rooted under
        // /private/tmp so the whole path is symlink-free and pwd's output
        // is byte-comparable.
        let storagePath = "/private/tmp/TartManager storage \(UUID().uuidString)/storage with space"
        let vmDirPath = storagePath + "/vms/vm-a"
        try FileManager.default.createDirectory(atPath: vmDirPath, withIntermediateDirectories: true)
        // A macOS guest: the run must keep the suspendable flag alongside the
        // pinned working directory.
        try #"{"os":"darwin"}"#.write(toFile: vmDirPath + "/config.json",
                                      atomically: true, encoding: .utf8)
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$PWD" >> "\(invocationFile)"
        echo "$@" >> "\(invocationFile)"
        sleep 30
        """)
        let staleSocket = vmDirPath + "/" + TartClient.controlSocketFilename
        FileManager.default.createFile(atPath: staleSocket, contents: nil)
        let client = TartClient(
            binaryPath: stub,
            environment: TartCommandEnvironment(storagePath: storagePath).environment)
        let handle = try client.runVM(
            name: "vm-a", earlyFailureWindow: 0.3, logDirectory: dir)
        defer {
            handle.process.terminate()
            handle.process.waitUntilExit()
        }
        // The stale socket is removed before the child spawns.
        #expect(!FileManager.default.fileExists(atPath: staleSocket))
        let lines = CaptureFile.waitForLines(atPath: invocationFile, count: 2)
        // The child runs from the VM's own directory, per-VM isolated.
        #expect(lines.contains(vmDirPath))
        #expect(lines.contains("run --suspendable vm-a"))
    }
}
