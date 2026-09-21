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
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$TART_HOME" >> "\(invocationFile)"
        echo "$@" >> "\(invocationFile)"
        sleep 30
        """)
        let client = TartClient(
            binaryPath: stub,
            environment: TartCommandEnvironment(storagePath: "/tmp/run-home").environment)
        let handle = try client.runVM(
            name: "vm-a", earlyFailureWindow: 0.3, logDirectory: dir)
        defer {
            handle.process.terminate()
            handle.process.waitUntilExit()
        }
        // The stub needs a moment to be scheduled and write its captures;
        // poll instead of racing the read.
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: invocationFile),
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let lines = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(lines.contains("/tmp/run-home"))
        #expect(lines.contains("run --suspendable vm-a"))
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
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: invocationFile),
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let lines = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        // The child runs from the VM's own directory, per-VM isolated.
        #expect(lines.contains(vmDirPath))
        #expect(lines.contains("run --suspendable vm-a"))
    }
}
