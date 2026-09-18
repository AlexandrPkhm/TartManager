import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientReplaceDiskTests {
    @Test func replaceDiskSendsNameAndPath() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        try client.replaceDisk(name: "vm-a", withPath: "/images/clean.img")
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "set vm-a --disk /images/clean.img")
    }

    @Test func replaceDiskFailureThrowsCommandFailed() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'VM is running' 1>&2\nexit 8\n")
        let client = TartClient(binaryPath: stub)
        do {
            try client.replaceDisk(name: "vm-a", withPath: "/images/clean.img")
            Issue.record("expected commandFailed")
        } catch let error as TartClientError {
            guard case .commandFailed(let command, let exitCode, let stdout, let stderr) = error else {
                Issue.record("expected .commandFailed, got \(error)")
                return
            }
            #expect(command == "set")
            #expect(exitCode == 8)
            #expect(stdout == "")
            #expect(stderr.contains("running"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func replaceDiskRejectsLeadingDashPath() throws {
        // Finding 8: the user-controlled path can never be parsed as a flag —
        // refused before any subprocess (Issue 11's guard, re-applied).
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        do {
            try client.replaceDisk(name: "vm-a", withPath: "-h.img")
            Issue.record("expected commandFailed")
        } catch let error as TartClientError {
            guard case .commandFailed(let command, let exitCode, _, let stderr) = error else {
                Issue.record("expected .commandFailed, got \(error)")
                return
            }
            #expect(command == "set")
            #expect(exitCode == -1)
            #expect(stderr.contains("beginning with '-'"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }

    @Test func replaceDiskStreamsToCompletionWithoutADeadline() throws {
        // Finding 3: the multi-GB copy must run through the streaming runner,
        // whose API carries no ProcessRunner deadline. The stub emits a chunk
        // (drained deterministically before waitForExit returns, Issue 9).
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'copying disk'\nexit 0\n")
        let client = TartClient(binaryPath: stub)
        let collected = LockedValue("")
        try client.replaceDisk(name: "vm-a", withPath: "/images/clean.img") { chunk in
            collected.withValue { $0 += chunk }
        }
        #expect(collected.value.contains("copying disk"))
    }
}
