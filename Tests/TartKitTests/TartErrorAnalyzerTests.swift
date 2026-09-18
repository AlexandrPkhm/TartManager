import Testing
import Foundation
@testable import TartKit

@Suite struct TartErrorAnalyzerTests {
    @Test func messageIsFirstStderrLineWithoutErrorPrefix() {
        let error = TartErrorAnalyzer.analyze(
            command: "run", exitCode: 12,
            stdout: "",
            stderr: "Error: failed to start VM\nsome context line\nanother")
        #expect(error.message == "failed to start VM")
        #expect(error.operation == "run")
        #expect(error.hint == nil)
        #expect(error.exitCode == 12)
    }

    @Test func messageFallsBackToExitCodeWhenStderrEmpty() {
        let error = TartErrorAnalyzer.analyze(command: "stop", exitCode: 3, stdout: "", stderr: "\n \n")
        #expect(error.message == "tart exited with code 3")
    }

    @Test func rawDetailsPreserveEverythingVerbatim() {
        let error = TartErrorAnalyzer.analyze(
            command: "stop", exitCode: 5,
            stdout: "OUT-LINE", stderr: "ERR-LINE")
        #expect(error.rawDetails.contains("stop"))
        #expect(error.rawDetails.contains("exit code: 5"))
        #expect(error.rawDetails.contains("ERR-LINE"))
        #expect(error.rawDetails.contains("OUT-LINE"))
    }

    @Test func knownCrossVersionFailureGetsHint() {
        // Golden text captured from a real session (Parallels diagnosis, Sep 17 2026):
        let raw = """
        Failed to start macVM: An error occurred during installation. Installation failed.
        at some internal frame
        """
        let error = TartErrorAnalyzer.analyze(command: "create", exitCode: 1, stdout: "", stderr: raw)
        #expect(error.message.contains("An error occurred during installation"))
        #expect(error.hint != nil)
        // Assert the hint's actual wording ("matches the host" + "prebuilt"),
        // not the word "same", which the hint never contains (finding 1).
        #expect(error.hint!.contains("matches the host"))
        #expect(error.hint!.contains("prebuilt"))
        #expect(error.exitCode == 1)
    }

    @Test func copyReportIsDeterministicAndComplete() {
        let error = TartErrorAnalyzer.analyze(
            command: "stop", exitCode: 5, stdout: "OUT", stderr: "ERR")
        let report = error.copyReport()
        #expect(report.contains("Tart Manager error report"))
        #expect(report.contains("operation: stop"))
        #expect(report.contains("exit code: 5"))
        #expect(report.contains("ERR"))
    }

    @Test func redactionAppliesBeforeMessageAndRawDetails() {
        // The universal contract carries a scrubbing hook so future
        // credential-touching operations (registry login) never leak secrets
        // into the message, raw details, copy payload, or log.
        let redact: @Sendable (String) -> String = {
            $0.replacingOccurrences(of: "s3cret-token", with: "******")
        }
        let error = TartErrorAnalyzer.analyze(
            command: "login", exitCode: 2,
            stdout: "",
            stderr: "Error: authentication failed for s3cret-token",
            redact: redact)
        #expect(error.message.contains("******"))
        #expect(!error.message.contains("s3cret-token"))
        #expect(!error.rawDetails.contains("s3cret-token"))
    }

    @Test func overlongOutputIsCappedPerStream() {
        // rawDetails never grows unbounded: each stream is capped at
        // maxCapturedCharactersPerStream; the head is kept with a
        // truncation marker.
        let big = String(repeating: "x", count: TartErrorAnalyzer.maxCapturedCharactersPerStream + 500)
        let error = TartErrorAnalyzer.analyze(
            command: "stop", exitCode: 1, stdout: big, stderr: "Error: small")
        #expect(error.rawDetails.contains("truncated"))
        #expect(error.rawDetails.contains("500"))
        // Count within the isolated stdout section: the report header itself
        // contains an "x" ("exit code"), so a whole-report count would be off
        // by one. The capped stream keeps exactly the budget of "x" payload.
        let stdoutSection = error.rawDetails.components(separatedBy: "--- stdout ---\n").last!
        #expect(stdoutSection.filter { $0 == "x" }.count
                == TartErrorAnalyzer.maxCapturedCharactersPerStream)
        #expect(error.rawDetails.contains("Error: small")) // small stream stays verbatim
        #expect(error.message == "small")
    }

    @Test func normalizedConvenienceIsTheSingleChokePoint() {
        // `.normalized` on the client error type is the only normalization
        // entry point app code uses; it must agree with the analyzer's
        // direct output. The payloads carry a fresh UUID identity each, so
        // agreement is checked on the deterministic copy report (everything
        // except identity) plus the structured fields.
        let raw = TartClientError.commandFailed(command: "list", exitCode: 7, stdout: "o", stderr: "Error: boom")
        let viaChokePoint = raw.normalized
        let direct = TartErrorAnalyzer.analyze(raw)
        #expect(viaChokePoint.copyReport() == direct.copyReport())
        #expect(viaChokePoint.operation == direct.operation)
        #expect(viaChokePoint.message == direct.message)
        #expect(viaChokePoint.rawDetails == direct.rawDetails)
        #expect(viaChokePoint.hint == direct.hint)
        #expect(viaChokePoint.exitCode == direct.exitCode)
        #expect(raw.normalized.exitCode == 7)
    }

    @Test func tartClientErrorIsSendable() {
        // TartClientError crosses Task.detached boundaries; pin the Sendable
        // conformance at compile time.
        func requireSendable<T: Sendable>(_ value: T) {}
        requireSendable(TartClientError.commandFailed(command: "stop", exitCode: 1, stdout: "", stderr: "x"))
    }

    @Test func nonCommandFailureCasesNormalizeHonestly() {
        // launchFailed/timedOut/decodingFailed must not masquerade as
        // commandFailed with fabricated exit codes.
        let timedOut = TartClientError.timedOut(command: "list", timeout: 10)
        let normalized = timedOut.normalized
        #expect(normalized.operation == "list")
        #expect(normalized.exitCode == nil)
        #expect(normalized.rawDetails.contains("10"))
    }

    @Test func suspendFailuresCarryTheSuspendHintOnTheRealRefusalText() throws {
        // Golden fixture: the exact stderr captured in Task 0 Step 2 from the
        // real host (tart 2.32), written verbatim into
        // Fixtures/tart-suspend-failure.stderr. On this tart version there is
        // no non-suspendable refusal (`tart suspend` succeeds on plain runs),
        // so the capture is the only real `tart suspend` failure the CLI
        // produces — suspending a stopped VM (exit code 2). The hint is
        // attached to *any* suspend failure, so it fires on this text and on
        // any tart version's refusal wording.
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tart-suspend-failure.stderr")
        let stderr = try String(contentsOf: fixtureURL, encoding: .utf8)
        let error = TartErrorAnalyzer.analyze(
            command: "suspend", exitCode: 2, stdout: "", stderr: stderr)
        #expect(error.hint != nil)
        #expect(error.hint!.contains("suspendable"))
        // The real text still yields the real first-line message.
        #expect(error.message.contains("not running"))
    }

    @Test func otherCommandsDoNotGetTheSuspendHint() {
        let error = TartErrorAnalyzer.analyze(
            command: "stop", exitCode: 1, stdout: "", stderr: "something failed")
        #expect(error.hint == nil)
    }

    @Test func stdinDeliveryFailureNormalizesHonestly() {
        // The honest case: no fabricated exit code, `exitCode` stays nil.
        let normalized = TartClientError.stdinDeliveryFailed(command: "login").normalized
        #expect(normalized.operation == "login")
        #expect(normalized.exitCode == nil)
        #expect(normalized.message.contains("did not read"))
    }

    @Test func normalizedWithRedactScrubsBeforeMessageAndRawDetails() {
        // The redaction hook wires into the choke point: the scrubber runs
        // before message/rawDetails are built, so the sheet, the clipboard,
        // and the log all receive scrubbed text.
        let raw = TartClientError.commandFailed(
            command: "login", exitCode: 2, stdout: "",
            stderr: "Error: authentication failed for tok-123")
        let normalized = raw.normalized(redact: RegistryCredentialScrubber.redactor(secret: "tok-123"))
        #expect(normalized.message.contains("******"))
        #expect(!normalized.message.contains("tok-123"))
        #expect(!normalized.rawDetails.contains("tok-123"))
    }
}
