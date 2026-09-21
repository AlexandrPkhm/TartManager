import Testing
import Foundation
@testable import TartKit

@Suite struct ProcessRunnerTests {
    @Test func capturesStdoutStderrAndExitCode() throws {
        let result = try ProcessRunner().run(
            "/bin/sh", ["-c", "echo out; echo err 1>&2; exit 3"])
        #expect(result.exitCode == 3)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "out")
        #expect(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines) == "err")
    }

    @Test func injectsEnvironmentVariables() throws {
        let result = try ProcessRunner().run(
            "/bin/sh", ["-c", "echo $TARTMANAGER_TEST_VAR"],
            environment: ["TARTMANAGER_TEST_VAR": "injected"])
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "injected")
    }

    /// tart 2.32.1 binds its per-VM control socket relative to the child's
    /// working directory (its own chdir into the VM directory fails on
    /// percent-encoded storage paths — any path with a space), so the runner
    /// must be able to pin a working directory, spaces included.
    @Test func runsInTheGivenWorkingDirectory() throws {
        // Under /private/tmp so pwd's physical output is byte-comparable:
        // every component is symlink-free (the /var-based
        // temporaryDirectory would print its /private physical form).
        let dirPath = "/private/tmp/TartManager space test \(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        let result = try ProcessRunner().run(
            "/bin/sh", ["-c", "pwd"], workingDirectory: dirPath)
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == dirPath)
    }

    @Test func throwsWhenExecutableDoesNotExist() {
        #expect(throws: ProcessRunnerError.self) {
            _ = try ProcessRunner().run("/nonexistent/binary", ["--version"])
        }
    }

    /// Regression for review finding 1: a child that fills the stderr pipe
    /// (64 KB buffer) before closing stdout used to deadlock the
    /// drain-stdout-first order.
    @Test func doesNotDeadlockWhenStderrFillsFirst() throws {
        let result = try ProcessRunner().run(
            "/bin/sh", ["-c", "head -c 200000 /dev/zero 1>&2; echo done"])
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "done")
        #expect(result.stderr.count == 200000)
    }

    @Test func drainsLargeStdoutAndStderr() throws {
        let result = try ProcessRunner().run(
            "/bin/sh", ["-c", "head -c 200000 /dev/zero; head -c 200000 /dev/zero 1>&2; exit 0"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.count == 200000)
        #expect(result.stderr.count == 200000)
    }

    /// Regression for review finding 2 (timeout half): a wedged child is
    /// terminated and surfaced as `.timedOut` instead of blocking forever.
    @Test func terminatesAProcessThatIgnoresTheDeadline() {
        do {
            _ = try ProcessRunner().run("/bin/sh", ["-c", "sleep 30"], timeout: 0.5)
            Issue.record("expected ProcessRunnerError.timedOut")
        } catch let error as ProcessRunnerError {
            guard case .timedOut = error else {
                Issue.record("expected .timedOut, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }
}
