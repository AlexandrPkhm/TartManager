import Testing
import Foundation
@testable import TartKit

@Suite struct ProcessRunnerInputTests {
    @Test func deliversInputViaStdinNotArgv() throws {
        let (stub, invocationFile, stdinFile) = StubBinary.makeRecordingStubWithStdinCapture()
        let result = try ProcessRunner().run(
            stub, ["some", "arguments"],
            input: "SECRET-token-value")

        #expect(result.exitCode == 0)
        let invocation = try String(contentsOfFile: invocationFile, encoding: .utf8)
        #expect(invocation.contains("some arguments"))
        #expect(!invocation.contains("SECRET-token-value"))   // never on the command line
        let secret = try String(contentsOfFile: stdinFile, encoding: .utf8)
        #expect(secret.trimmingCharacters(in: .whitespacesAndNewlines) == "SECRET-token-value")
    }

    @Test func existingCallSitesStaySourceCompatible() throws {
        let result = try ProcessRunner().run("/bin/sh", ["-c", "echo plain"])
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "plain")
    }

    /// Regression: a child that fails before consuming stdin must surface
    /// its own exit code and stderr — never a bogus `.failedToLaunch`. This
    /// test also pins the SIGPIPE fix: without `signal(SIGPIPE, SIG_IGN)`
    /// the write kills the whole test process (exit 141), so a green run
    /// proves the disposition is handled.
    @Test func fastFailingChildSurfacesItsOwnFailure() throws {
        let stub = StubBinary.make(script: "#!/bin/sh\necho boom 1>&2\nexit 7\n")
        let result = try ProcessRunner().run(stub, [], input: "SECRET-token-value")
        #expect(result.exitCode == 7)
        #expect(result.stderr.contains("boom"))
    }

    /// The pure classification behind the EPIPE tolerance: the failed write
    /// matters only when the child still claims success — then the credential
    /// never reached tart. Any non-zero exit is the child's own failure and
    /// is returned verbatim.
    @Test func inputDeliveryFailureDecisionIsPure() {
        #expect(ProcessRunner.inputDeliveryShouldFail(exitCode: 0, writeFailed: false) == false)
        #expect(ProcessRunner.inputDeliveryShouldFail(exitCode: 0, writeFailed: true))
        #expect(ProcessRunner.inputDeliveryShouldFail(exitCode: 7, writeFailed: true) == false)
        #expect(ProcessRunner.inputDeliveryShouldFail(exitCode: 7, writeFailed: false) == false)
    }
}
