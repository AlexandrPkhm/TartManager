import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientSuspendTests {
    func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir
    }

    @Test func suspendSendsNameWithStorageHome() async throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$TART_HOME $@" >> "\(invocationFile)"
        """)
        let client = TartClient(
            binaryPath: stub,
            environment: TartCommandEnvironment(storagePath: "/tmp/suspend-home").environment)
        try await client.suspend(name: "vm-a")
        let line = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "/tmp/suspend-home suspend vm-a")
    }

    @Test func suspendFailureCapturesStderrAndExitCode() async {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'not suspendable' 1>&2\nexit 6\n")
        let client = TartClient(binaryPath: stub)
        do {
            try await client.suspend(name: "vm-a")
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "suspend")
            #expect(exitCode == 6)
            #expect(stderr.contains("not suspendable"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func suspendTimeoutMapsToTimedOut() async {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub, timeout: 0.5)
        do {
            try await client.suspend(name: "vm-a")
            Issue.record("expected timedOut")
        } catch let TartClientError.timedOut(command, _) {
            // The shared mapping passes the runner's full invocation string
            // for timedOut (pre-existing ProcessRunner contract); the
            // commandFailed path carries the bare label.
            #expect(command.hasSuffix(" suspend vm-a"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
