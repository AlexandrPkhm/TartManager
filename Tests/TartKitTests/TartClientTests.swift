import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientTests {
    @Test func listParsesEntriesAndInjectsTartHome() throws {
        let captureDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: captureDir.path, withIntermediateDirectories: true)
        let script = #"""
        #!/bin/sh
        echo "$TART_HOME" > "\#(captureDir.path)/home.txt"
        echo '[{"Name":"vm","Source":"local","State":"stopped"}]'
        """#
        let stub = StubBinary.make(script: script)
        let client = TartClient(
            binaryPath: stub,
            environment: TartCommandEnvironment(storagePath: "/tmp/expected-home").environment)
        let entries = try client.list()
        #expect(entries.map(\.name) == ["vm"])
        let captured = try String(contentsOfFile: captureDir.appendingPathComponent("home.txt").path, encoding: .utf8)
        #expect(captured.trimmingCharacters(in: .whitespacesAndNewlines) == "/tmp/expected-home")
    }

    @Test func listCapturesCommandFailure() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'boom' 1>&2\nexit 9\n")
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.list()
            Issue.record("expected TartClientError.commandFailed")
        } catch let error as TartClientError {
            guard case .commandFailed(let command, let exitCode, _, let stderr) = error else {
                Issue.record("expected .commandFailed, got \(error)")
                return
            }
            #expect(command == "list")
            #expect(exitCode == 9)
            #expect(stderr.contains("boom"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func listWrapsLaunchFailureIntoClientError() {
        // Executable bit set but the interpreter is missing: Process.run() throws.
        let stub = StubBinary.make(script: "#!/nonexistent/interpreter\n")
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.list()
            Issue.record("expected TartClientError.launchFailed")
        } catch let error as TartClientError {
            guard case .launchFailed = error else {
                Issue.record("expected .launchFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func listWrapsTimeoutIntoClientError() {
        // A wedged tart must degrade to a typed error, never a hang (finding 5).
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub, timeout: 0.5)
        do {
            _ = try client.list()
            Issue.record("expected TartClientError.timedOut")
        } catch let error as TartClientError {
            guard case .timedOut = error else {
                Issue.record("expected .timedOut, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func listWrapsDecodeFailureIntoClientError() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'not json'\n")
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.list()
            Issue.record("expected TartClientError.decodingFailed")
        } catch let error as TartClientError {
            guard case .decodingFailed = error else {
                Issue.record("expected .decodingFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
