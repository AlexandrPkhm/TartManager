import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientExportTests {
    @Test func exportSendsNameAndPath() throws {
        let (stub, invocationFile) = StubBinary.makeRecordingStub()
        let client = TartClient(binaryPath: stub)
        let outcome = try client.export(name: "vm-a", to: "/tmp/out.tvm",
                                        onOutput: { _ in }, registerCancel: { _ in })
        #expect(outcome == .completed)
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(invocation == "export vm-a /tmp/out.tvm")
    }

    @Test func exportFailureThrowsNormalizedCommandFailed() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\necho 'disk full' 1>&2\nexit 7\n")
        let client = TartClient(binaryPath: stub)
        do {
            _ = try client.export(name: "vm-a", to: "/tmp/out.tvm",
                                  onOutput: { _ in }, registerCancel: { _ in })
            Issue.record("expected commandFailed")
        } catch let TartClientError.commandFailed(command, exitCode, _, stderr) {
            #expect(command == "export")
            #expect(exitCode == 7)
            #expect(stderr.contains("disk full"))
        }
    }

    @Test func exportLaunchFailureCarriesExportOperationLabel() {
        let client = TartClient(binaryPath: "/nonexistent/tart")
        do {
            _ = try client.export(name: "vm-a", to: "/tmp/x.tvm",
                                  onOutput: { _ in }, registerCancel: { _ in })
            Issue.record("expected to throw")
        } catch let error as TartClientError {
            #expect(error.normalized.operation == "export")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func exportReportsCancelledWhenCancelActionRuns() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = TartClient(binaryPath: stub)
        let outcome = try client.export(
            name: "slow-vm", to: "/tmp/out.tvm",
            onOutput: { _ in }) { cancel in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { cancel() }
            }
        #expect(outcome == .cancelled)
    }

    /// finding 10: export has no progress callback at all — output is raw
    /// passthrough for error capture/logging only; `PullProgressParser`
    /// (clone/pull-only) is never involved.
    @Test func exportStreamsRawOutputWithoutProgressParsing() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\necho '50%'\necho 'writing'\n")
        let chunks = TextAccumulator()
        _ = try TartClient(binaryPath: stub).export(
            name: "vm-a", to: "/tmp/out.tvm",
            onOutput: { chunks.append($0) },
            registerCancel: { _ in })
        #expect(chunks.value.contains("50%"))
        #expect(chunks.value.contains("writing"))
    }
}
