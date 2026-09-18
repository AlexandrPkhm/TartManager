import Testing
import Foundation
@testable import TartKit

@Suite struct StreamingProcessTests {
    @Test func streamsStdoutAndStderrAndCapturesExit() throws {
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "line one"
        echo "line two" 1>&2
        echo "line three"
        """)
        let streamed = TextAccumulator()
        let process = try StreamingProcess.launch(
            binaryPath: stub, arguments: [], environment: [:]) { chunk in
            streamed.append(chunk)
        }
        let exitCode = process.waitForExit()
        #expect(exitCode == 0)
        // Deterministic (finding 10): waitForExit awaits both streams' EOF,
        // so all output has been delivered before it returns.
        #expect(streamed.value.contains("line one"))
        #expect(streamed.value.contains("line two"))
        #expect(streamed.value.contains("line three"))
        #expect(process.combinedOutput.contains("line three"))
        #expect(!process.wasCancelled)
    }

    @Test func cancelTerminatesLongRunningProcess() async throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let process = try StreamingProcess.launch(
            binaryPath: stub, arguments: [], environment: [:]) { _ in }
        try await Task.sleep(for: .seconds(0.2))
        process.cancel()
        let exitCode = process.waitForExit()
        #expect(process.wasCancelled)
        #expect(exitCode != 0)
    }

    @Test func cancelEscalatesToSIGKILLWhenChildIgnoresTerm() async throws {
        // finding 9: a child that ignores SIGTERM must not strand the job.
        let stub = StubBinary.make(script: """
        #!/bin/sh
        trap '' TERM
        sleep 30
        """)
        let process = try StreamingProcess.launch(
            binaryPath: stub, arguments: [], environment: [:],
            terminationGrace: 0.3) { _ in }
        try await Task.sleep(for: .seconds(0.2))
        process.cancel()
        let started = Date()
        let exitCode = process.waitForExit()
        #expect(process.wasCancelled)
        #expect(exitCode != 0)
        #expect(Date().timeIntervalSince(started) < 5)  // SIGKILL cut the 30 s sleep short
    }

    @Test func missingExecutableThrowsSharedLaunchError() {
        // finding 7: one launch-failure definition across all runners.
        #expect(throws: ProcessRunnerError.self) {
            _ = try StreamingProcess.launch(
                binaryPath: "/nonexistent/stub", arguments: [], environment: [:]) { _ in }
        }
    }

    @Test func injectsEnvironmentViaSharedMerge() throws {
        // finding 7: env merging reuses ProcessEnvironment (same helper as
        // ProcessRunner), pinned by an end-to-end probe.
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo "$TARTMANAGER_STREAM_VAR"
        """)
        let streamed = TextAccumulator()
        let process = try StreamingProcess.launch(
            binaryPath: stub, arguments: [],
            environment: ["TARTMANAGER_STREAM_VAR": "injected"]) { streamed.append($0) }
        _ = process.waitForExit()
        #expect(streamed.value.contains("injected"))
    }

    @Test func combinedOutputIsBounded() throws {
        // finding 13: raw capture cannot grow with the session length.
        let stub = StubBinary.make(script: "#!/bin/sh\nhead -c 300000 /dev/zero | tr '\\0' 'x'\n")
        let process = try StreamingProcess.launch(
            binaryPath: stub, arguments: [], environment: [:]) { _ in }
        _ = process.waitForExit()
        #expect(process.combinedOutput.count <= TextAccumulator.maxBufferedCharacters + 64)
    }
}
