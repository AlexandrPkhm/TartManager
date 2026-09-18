import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientRenameTests {
    @Test func renameSendsOldAndNew() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        try client.rename(from: "vm-a", to: "vm-b")
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "rename vm-a vm-b")
    }

    @Test func renameFailureThrowsCommandFailed() throws {
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo 'VM is running' 1>&2
        exit 9
        """)
        let client = TartClient(binaryPath: stub)
        do {
            try client.rename(from: "vm-a", to: "vm-b")
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "rename")
            #expect(exitCode == 9)
            #expect(stderr.contains("running"))
        }
    }

    /// The Issue 11 guard, applied to rename: user-controlled values must
    /// never be parsed as tart flags.
    @Test func renameRejectsLeadingDashValues() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        do {
            try client.rename(from: "-a", to: "vm-b")
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "rename")
            #expect(exitCode == -1)
            #expect(stderr.contains("beginning with '-'"))
        }
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }
}
