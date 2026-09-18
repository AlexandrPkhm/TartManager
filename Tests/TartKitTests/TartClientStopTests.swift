import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientStopTests {
    func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir
    }

    func invocationLine(in dir: URL) throws -> String {
        try String(contentsOfFile: dir.appendingPathComponent("invocation.txt").path,
                   encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test func stopPassesNameWithNoTimeoutFlagAndStorageHome() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$TART_HOME $@" >> "\(invocationFile)"
        """)
        let client = TartClient(
            binaryPath: stub,
            environment: TartCommandEnvironment(storagePath: "/tmp/stop-home").environment)
        try await client.stop(name: "vm-a")
        // The default passes no --timeout flag: tart's own 30 s grace period
        // (with its automatic force fallback) applies.
        #expect(try invocationLine(in: dir) == "/tmp/stop-home stop vm-a")
    }

    @Test func stopPassesExplicitTimeout() async throws {
        // Exercises the explicit non-zero timeout branch.
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        """)
        let client = TartClient(binaryPath: stub)
        try await client.stop(name: "vm-a", timeout: 15)
        #expect(try invocationLine(in: dir) == "stop vm-a --timeout 15")
    }

    @Test func forceStopPassesZeroTimeout() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        """)
        let client = TartClient(binaryPath: stub)
        try await client.stop(name: "vm-a", timeout: 0)
        #expect(try invocationLine(in: dir) == "stop vm-a --timeout 0")
    }

    @Test func stopFailureCapturesStderr() async {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'not running' 1>&2\nexit 5\n")
        let client = TartClient(binaryPath: stub)
        do {
            try await client.stop(name: "vm-a")
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "stop")
            #expect(exitCode == 5)
            #expect(stderr.contains("not running"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func stopCommandTimeoutExceedsTartGracePeriod() {
        // The runner's 10 s default would kill a graceful stop mid-shutdown;
        // the stop subprocess deadline must cover tart's full 30 s grace
        // period plus its automatic force termination.
        #expect(TartClient.stopCommandTimeout > 30)
    }
}
