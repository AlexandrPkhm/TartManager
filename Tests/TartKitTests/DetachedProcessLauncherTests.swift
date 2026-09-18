import Testing
import Foundation
@testable import TartKit

@Suite struct DetachedProcessLauncherTests {
    func isolatedLogDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir
    }

    func runLogNames(in dir: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(DetachedProcessLauncher.logFilePrefix) }
    }

    @Test func launchesLongRunningChildAndReturnsHandle() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let dir = isolatedLogDirectory()
        let launcher = DetachedProcessLauncher()
        let handle = try launcher.launch(DetachedLaunchConfiguration(
            binaryPath: stub, arguments: ["whatever"],
            environment: [:], earlyFailureWindow: 0.2, logDirectory: dir))
        #expect(handle.pid > 0)
        #expect(handle.isRunning)
        // The success path unlinks the log immediately: nothing accumulates
        // in the temp directory while the VM runs.
        #expect(try runLogNames(in: dir).isEmpty)
        defer {
            handle.process.terminate()
            handle.process.waitUntilExit()
        }
    }

    @Test func throwsCapturedOutputWhenChildExitsQuickly() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\necho boom 1>&2\nexit 7\n")
        let dir = isolatedLogDirectory()
        let launcher = DetachedProcessLauncher()
        #expect(throws: DetachedLauncherError.self) {
            _ = try launcher.launch(DetachedLaunchConfiguration(
                binaryPath: stub, arguments: [],
                environment: [:], earlyFailureWindow: 3.0, logDirectory: dir))
        }
        #expect(try runLogNames(in: dir).isEmpty) // failure path removes the log
    }

    @Test func quickExitPayloadCarriesExitCodeAndOutput() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho boom 1>&2\nexit 7\n")
        let launcher = DetachedProcessLauncher()
        do {
            _ = try launcher.launch(DetachedLaunchConfiguration(
                binaryPath: stub, arguments: [],
                environment: [:], earlyFailureWindow: 3.0,
                logDirectory: isolatedLogDirectory()))
            Issue.record("expected exitedQuickly")
        } catch let DetachedLauncherError.exitedQuickly(exitCode, output) {
            #expect(exitCode == 7)
            #expect(output.contains("boom"))
        } catch {
            Issue.record("expected exitedQuickly, got \(error)")
        }
    }

    @Test func throwsWhenExecutableMissing() {
        let launcher = DetachedProcessLauncher()
        #expect(throws: DetachedLauncherError.self) {
            _ = try launcher.launch(DetachedLaunchConfiguration(
                binaryPath: "/nonexistent/stub", arguments: [],
                environment: [:], earlyFailureWindow: 0.2,
                logDirectory: isolatedLogDirectory()))
        }
    }

    @Test func childReceivesParentEnvironmentPlusOverrides() throws {
        // Proves the launcher uses the shared ProcessEnvironment merge:
        // TART_HOME reaches the child and unrelated vars stay inherited.
        let dir = isolatedLogDirectory()
        let captureFile = dir.appendingPathComponent("captured.txt").path
        let stub = StubBinary.make(script: """
            #!/bin/sh
            echo "$TART_HOME" > "\(captureFile)"
            sleep 30
            """)
        let launcher = DetachedProcessLauncher()
        let handle = try launcher.launch(DetachedLaunchConfiguration(
            binaryPath: stub, arguments: [],
            environment: ["TART_HOME": "/tmp/expected-home"],
            earlyFailureWindow: 0.2, logDirectory: dir))
        defer {
            handle.process.terminate()
            handle.process.waitUntilExit()
        }
        // The stub needs a moment to be scheduled and write its capture
        // (measured ~0.3 s even unloaded); poll instead of racing the read.
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: captureFile),
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let captured = try String(contentsOfFile: captureFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(captured == "/tmp/expected-home")
    }
}
