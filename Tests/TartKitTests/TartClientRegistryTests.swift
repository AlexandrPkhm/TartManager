import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientRegistryTests {
    @Test func loginSendsHostUsernameAndSecretViaStdin() throws {
        let (stub, invocationFile, stdinFile) = StubBinary.makeRecordingStubWithStdinCapture()
        let client = TartClient(binaryPath: stub)
        try client.login(host: "ghcr.io", username: "ci-bot", password: "tok-123")

        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "login ghcr.io --username ci-bot --password-stdin")
        #expect(!invocation.contains("tok-123"))
        let secret = try String(contentsOfFile: stdinFile, encoding: .utf8)
        #expect(secret.trimmingCharacters(in: .whitespacesAndNewlines) == "tok-123")
    }

    @Test func logoutSendsHost() throws {
        let (stub, invocationFile, _) = StubBinary.makeRecordingStubWithStdinCapture()
        let client = TartClient(binaryPath: stub)
        try client.logout(host: "ghcr.io")
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "logout ghcr.io")
    }

    /// Fast-failing tart exits 7 before consuming stdin. The runner's
    /// EPIPE-tolerant delivery returns tart's own exit code + stderr — never
    /// a bogus failedToLaunch. Deterministic: both write races converge on
    /// exit code 7.
    @Test func loginFailureThrowsCommandFailed() throws {
        let stub = StubBinary.make(script: """
            #!/bin/sh
            echo 'invalid credentials' 1>&2
            exit 7
            """)
        let client = TartClient(binaryPath: stub)
        do {
            try client.login(host: "ghcr.io", username: "u", password: "p")
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "login")
            #expect(exitCode == 7)
            #expect(stderr.contains("invalid credentials"))
        }
    }

    /// A wedged login degrades to `.timedOut` under the dedicated auth
    /// deadline — never an indefinite hang.
    @Test func loginTimeoutSurfacesAsTimedOut() {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub, authTimeout: 0.5)
        do {
            try client.login(host: "ghcr.io", username: "u", password: "p")
            Issue.record("expected timedOut")
        } catch let error as TartClientError {
            guard case .timedOut = error else {
                Issue.record("expected .timedOut, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    /// Empty fields and hostile hosts throw BEFORE any subprocess runs: the
    /// stub writes a marker file only if it is executed.
    @Test func loginRejectsEmptyFieldsAndHostileHostsBeforeAnyProcessRuns() {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-marker-\(UUID().uuidString)").path
        let stub = StubBinary.make(script: "#!/bin/sh\ntouch \"\(marker)\"\nexit 0\n")
        let client = TartClient(binaryPath: stub)

        func expectRejected(host: String, username: String, password: String,
                            _ check: (RegistryArgumentError) -> Bool) {
            do {
                try client.login(host: host, username: username, password: password)
                Issue.record("expected RegistryArgumentError")
            } catch let error as RegistryArgumentError {
                #expect(check(error))
            } catch {
                Issue.record("expected RegistryArgumentError, got \(error)")
            }
        }

        expectRejected(host: "", username: "u", password: "p") { error in
            guard case .emptyField(let command, let field) = error else { return false }
            return command == "login" && field == "host"
        }
        expectRejected(host: "ghcr.io", username: "", password: "p") { error in
            guard case .emptyField(_, let field) = error else { return false }
            return field == "username"
        }
        expectRejected(host: "ghcr.io", username: "u", password: "") { error in
            guard case .emptyField(_, let field) = error else { return false }
            return field == "password"
        }
        expectRejected(host: "-evil", username: "u", password: "p") { error in
            if case .invalidHost = error { return true }
            return false
        }
        expectRejected(host: "gh cr.io", username: "u", password: "p") { error in
            if case .invalidHost = error { return true }
            return false
        }
        expectRejected(host: "gh\u{07}cr.io", username: "u", password: "p") { error in
            if case .invalidHost = error { return true }
            return false
        }
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test func logoutRejectsHostileHost() {
        let stub = StubBinary.makeRecordingStubWithStdinCapture().stubPath
        let client = TartClient(binaryPath: stub)
        do {
            try client.logout(host: "-evil")
            Issue.record("expected RegistryArgumentError")
        } catch let error as RegistryArgumentError {
            guard case .invalidHost(let command, _) = error, command == "logout" else {
                Issue.record("expected invalidHost(command: \"logout\"), got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
