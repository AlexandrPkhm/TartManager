import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientPruneTests {
    @Test func pruneSendsEntriesAndRetention() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        var chunks: [String] = []
        let outcome = try client.prune(olderThanDays: 14) { chunk in
            chunks.append(chunk)
        }
        #expect(outcome == .completed)
        // Verified: tart 2.32.0 prune is silent on the success path — the
        // client treats empty output as success, never as a signal.
        #expect(chunks.isEmpty)
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "prune --entries caches --older-than 14")
    }

    @Test func pruneRejectsNonPositiveRetention() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        for days in [0, -3] {
            do {
                _ = try client.prune(olderThanDays: days) { _ in }
                Issue.record("expected commandFailed for \(days)")
            } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
                #expect(command == "prune")
                #expect(exitCode == -1)
                #expect(stderr.contains("positive"))
            }
        }
        // Validation happens before any launch — the binary never ran.
        #expect(!FileManager.default.fileExists(atPath: invocationFile))
    }

    @Test func pruneFailureThrowsCommandFailed() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'disk full' 1>&2\nexit 7\n")
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.prune(olderThanDays: 14) { _ in }
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "prune")
            #expect(exitCode == 7)
            #expect(stderr.contains("disk full"))
        }
    }

    /// finding 8: a prune launch failure carries the "prune" operation
    /// label, never "job".
    @Test func pruneLaunchFailureCarriesPruneLabel() {
        let client = TartClient(binaryPath: "/nonexistent/tart")
        do {
            _ = try client.prune(olderThanDays: 14) { _ in }
            Issue.record("expected to throw")
        } catch let TartClientError.launchFailed(command, executable) {
            #expect(command == "prune")
            #expect(executable == "/nonexistent/tart")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func pruneReportsCancelledWhenCancelActionRuns() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub)
        let outcome = try client.prune(olderThanDays: 14, onOutput: { _ in }) { cancel in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { cancel() }
        }
        #expect(outcome == .cancelled)
    }
}
