import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientImportDeleteTests {
    @Test func importSendsPathAndNameAndCompletes() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        let outcome = try client.importArchive(
            at: "/tmp/archive.tvm", to: "restored-vm",
            onOutput: { _ in }, registerCancel: { _ in })
        #expect(outcome == .completed)
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "import /tmp/archive.tvm restored-vm")
    }

    @Test func importFailureThrowsNormalizedCommandFailed() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'not a tart archive' 1>&2\nexit 4\n")
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.importArchive(at: "/tmp/bad.tvm", to: "x",
                                         onOutput: { _ in }, registerCancel: { _ in })
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "import")
            #expect(exitCode == 4)
            #expect(stderr.contains("not a tart archive"))
        }
    }

    @Test func importCancelReturnsCancelled() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub)
        let outcome = try client.importArchive(
            at: "/tmp/archive.tvm", to: "slow-vm",
            onOutput: { _ in }) { cancel in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { cancel() }
            }
        #expect(outcome == .cancelled)
    }

    @Test func deleteSendsName() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        try client.delete(name: "partial-junk")
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "delete partial-junk")
    }

    @Test func deleteFailureThrowsCommandFailed() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'VM is running' 1>&2\nexit 4\n")
        let client = TartClient(binaryPath: stub)
        do {
            try client.delete(name: "vm-a")
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "delete")
            #expect(exitCode == 4)
            #expect(stderr.contains("running"))
        }
    }

    /// Finding 11: a wedged delete must surface as `.timedOut`, never hang.
    @Test func deleteTimesOutOnWedgedBinary() {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub, timeout: 0.5)
        do {
            try client.delete(name: "vm-a")
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

    /// Finding 10: leading-dash values are refused before any subprocess runs.
    @Test func importRejectsLeadingDashPath() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.importArchive(at: "-h.tvm", to: "vm",
                                         onOutput: { _ in }, registerCancel: { _ in })
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "import")
            #expect(exitCode == -1)
            #expect(stderr.contains("beginning with '-'"))
        }
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }

    @Test func deleteRejectsLeadingDashName() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        do {
            try client.delete(name: "-v")
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "delete")
            #expect(exitCode == -1)
            #expect(stderr.contains("beginning with '-'"))
        }
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }
}
