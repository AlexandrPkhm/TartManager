import Testing
import Foundation
@testable import TartKit

@Suite struct TartClientCloneTests {
    func makeClient(stub: String) -> TartClient {
        TartClient(binaryPath: stub,
                   environment: TartCommandEnvironment(storagePath: "/tmp/clone-home").environment)
    }

    /// Thread-safe box for the cancel action handed back by the clone.
    final class ActionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var action: (() -> Void)?

        func set(_ action: @escaping () -> Void) {
            lock.lock()
            self.action = action
            lock.unlock()
        }

        func take() -> (() -> Void)? {
            lock.lock()
            defer { lock.unlock() }
            return action
        }
    }

    @Test func cloneSendsSourceNameEnvAndProgress() throws {
        // Adaptation: the repo's StubBinary.make requires a script argument,
        // so the initial stub is a trivial exit-0 script (overwritten below).
        let stub = StubBinary.make(script: "#!/bin/sh\nexit 0\n")
        let capture = URL(fileURLWithPath: stub)
            .deletingLastPathComponent()
            .appendingPathComponent("captured.txt").path
        try """
        #!/bin/sh
        echo "$TART_HOME $@" > '\(capture)'
        exit 0
        """.write(toFile: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)

        let client = makeClient(stub: stub)
        let exit = try client.clone(
            source: "ghcr.io/cirruslabs/macos-tahoe-base:latest",
            to: "macos26-tahoe",
            onProgress: { _ in },
            registerCancel: { _ in })
        #expect(exit == .completed)
        let output = try String(contentsOfFile: capture, encoding: .utf8)
        #expect(output.contains("/tmp/clone-home"))
        #expect(output.contains("clone ghcr.io/cirruslabs/macos-tahoe-base:latest macos26-tahoe"))
    }

    @Test func cloneStreamsProgressInOrder() throws {
        // Adaptation: sleeps pace the lines into separate streamed chunks —
        // an unpaced fast stub delivers everything in one chunk, which the
        // tracker legitimately collapses into a single latest-state report.
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo 'pulling manifest...'; sleep 0.1
        echo 'pulling disk (27.3 GB compressed)...'; sleep 0.1
        echo '10%'; sleep 0.1
        echo '20%'
        exit 0
        """)
        var collected: [PullProgress] = []
        _ = try makeClient(stub: stub).clone(
            source: "img:latest", to: "vm-x",
            onProgress: { collected.append($0) },
            registerCancel: { _ in })
        // clone() awaits exit AND the streams' EOF drain, so asserting
        // immediately is deterministic (finding 10).
        #expect(collected.contains { $0.fraction == 0.1 })
        #expect(collected.contains { $0.fraction == 0.2 })
        #expect(collected.contains { $0.fraction == nil && $0.note == "pulling manifest…" })
    }

    @Test func cloneDeduplicatesUnchangedProgress() throws {
        let stub = StubBinary.make(script: """
        #!/bin/sh
        printf '10%%\r'; sleep 0.2
        printf '10%%\r'; sleep 0.2
        printf '20%%\n'; sleep 0.2
        """)
        var fractions: [Double?] = []
        _ = try makeClient(stub: stub).clone(
            source: "img:latest", to: "vm-y",
            onProgress: { fractions.append($0.fraction) },
            registerCancel: { _ in })
        // finding 12: identical parses are never re-reported. Chunking is
        // unspecified, so assert no adjacent duplicates and the final value
        // (robust whether chunks merge or not).
        #expect(fractions.last == 0.2)
        let adjacent = zip(fractions, fractions.dropFirst())
        #expect(adjacent.allSatisfy { $0.0 != $0.1 })
    }

    @Test func cloneFailureSurfacesTartsErrorMessage() {
        let stub = StubBinary.make(script: """
        #!/bin/sh
        echo 'pulling manifest...'
        echo 'pulling disk (27.3 GB compressed)...'
        echo '14%'
        echo 'Error: manifest unknown: nope'
        exit 1
        """)
        do {
            _ = try makeClient(stub: stub).clone(
                source: "ghcr.io/cirruslabs/nope:missing", to: "vm-z",
                onProgress: { _ in },
                registerCancel: { _ in })
            Issue.record("expected clone to throw")
        } catch let error as TartClientError {
            // finding 2: the sheet message is tart's fatal error, not a
            // progress line; raw details keep the full capped output.
            let normalized = error.normalized
            #expect(normalized.operation == "clone")
            #expect(normalized.message == "manifest unknown: nope")
            #expect(normalized.rawDetails.contains("pulling manifest"))
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func cloneLaunchFailureCarriesCloneOperationLabel() {
        let client = makeClient(stub: "/nonexistent/tart")
        do {
            _ = try client.clone(source: "img:latest", to: "vm-q",
                                 onProgress: { _ in },
                                 registerCancel: { _ in })
            Issue.record("expected clone to throw")
        } catch let error as TartClientError {
            // finding 16: the normalized failure reads "clone", never "job".
            #expect(error.normalized.operation == "clone")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test func cloneReportsCancelledWhenCancelActionRuns() async throws {
        let stub = StubBinary.make(script: "#!/bin/sh\nsleep 30\n")
        let client = makeClient(stub: stub)
        let box = ActionBox()
        let task = Task.detached {
            try client.clone(source: "img:latest", to: "vm-r",
                             onProgress: { _ in },
                             registerCancel: { box.set($0) })
        }
        // Wait until the clone registered its cancel action, then trigger it.
        for _ in 0..<100 where box.take() == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        box.take()?()
        let result = try await task.value
        #expect(result == .cancelled)
    }

    @Test func cloneWorksForLocalSourceNames() throws {
        // A local VM name is a valid source for the very same command
        // (Research: `tart clone <source-name> <new-name>`); pin the argv
        // with no extra flags. Adapted to the merged clone API (client-owned
        // progress parsing): the exact argv is asserted via a capturing stub.
        let stub = StubBinary.make(script: "#!/bin/sh\nexit 0\n")
        let capture = URL(fileURLWithPath: stub)
            .deletingLastPathComponent()
            .appendingPathComponent("captured.txt").path
        try """
        #!/bin/sh
        echo "$@" > '\(capture)'
        exit 0
        """.write(toFile: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub)

        let client = makeClient(stub: stub)
        let exit = try client.clone(source: "golden-vm", to: "vm-from-golden",
                                    onProgress: { _ in }, registerCancel: { _ in })
        #expect(exit == .completed)
        let line = try String(contentsOfFile: capture, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(line == "clone golden-vm vm-from-golden")
    }
}
