import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientExecTests {
    func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir
    }

    @Test func execSendsRightArgsAndReturnsTrimmedOutput() throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        printf 'ready\\n'
        """)
        let client = TartClient(binaryPath: stub)
        let output = try client.exec(name: "vm-a", command: "echo ready")
        #expect(output == "ready")
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "exec vm-a sh -lc echo ready")
    }

    @Test func execFailureThrowsCommandFailed() {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'Guest agent is not running' 1>&2\nexit 1\n")
        let client = TartClient(binaryPath: stub)
        #expect(throws: TartClientError.self) { _ = try client.exec(name: "vm-a", command: "echo ready") }
    }

    @Test func execTimeoutThrowsTimedOut() {
        // exec must run under TartClient's deadline, never hang.
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub, timeout: 0.5)
        do {
            _ = try client.exec(name: "vm-a", command: "echo ready")
            Issue.record("expected .timedOut")
        } catch let TartClientError.timedOut(command, _) {
            #expect(command.contains("exec vm-a sh -lc echo ready"))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func execRejectsVMNamesBeginningWithADash() throws {
        let dir = tempDir()
        let invocationFile = dir.appendingPathComponent("invocation.txt").path
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$@" >> "\(invocationFile)"
        """)
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.exec(name: "--flag", command: "echo ready")
            Issue.record("expected leading-dash refusal")
        } catch let TartClientError.commandFailed(command, exitCode, stdout, stderr) {
            #expect(command == "exec")
            #expect(exitCode == -1)
            #expect(stderr.contains("beginning with '-'"))
            _ = stdout
        }
        // Pre-spawn refusal: the stub was never invoked, so no invocation
        // file exists at all.
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }

    @Test func execRunsFromTheVMDirectoryWhenConfigured() throws {
        // /private/tmp root keeps the path symlink-free so pwd is
        // byte-comparable; see runVMLaunchesFromTheVMDirectoryAndRemovesAStaleControlSocket.
        let storagePath = "/private/tmp/TartManager storage \(UUID().uuidString)"
        let vmDirPath = storagePath + "/vms/vm-a"
        try FileManager.default.createDirectory(atPath: vmDirPath, withIntermediateDirectories: true)
        let invocationFile = storagePath + "/invocation.txt"
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$PWD" >> "\(invocationFile)"
        printf 'ready\\n'
        """)
        let client = TartClient(
            binaryPath: stub,
            environment: TartCommandEnvironment(storagePath: storagePath).environment)
        #expect(try client.exec(name: "vm-a", command: "echo ready") == "ready")
        let pwd = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(pwd == vmDirPath)
    }
}
