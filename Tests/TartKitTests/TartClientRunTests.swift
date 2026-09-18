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
}
