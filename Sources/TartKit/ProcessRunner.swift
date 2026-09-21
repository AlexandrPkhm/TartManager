import Darwin
import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum ProcessRunnerError: Error, Equatable {
    /// The executable could not be launched at the given path.
    case failedToLaunch(String)
    /// The process did not exit within the deadline and was terminated.
    case timedOut(command: String, timeout: TimeInterval)
    /// The child exited 0 without reading the input the app sent (the stdin
    /// write failed). Distinct from launch failure: the child did run, it
    /// just never consumed the delivered input.
    case inputWriteFailed(command: String)
}

/// Runs a subprocess and captures its exit code, stdout, and stderr.
///
/// stdout and stderr are drained concurrently so a child that fills one pipe
/// (the OS pipe buffer is 64 KB) cannot deadlock the run; a timeout terminates
/// children that never exit. This runner is the foundation for all later
/// slices, whose output (`list --format json`, clone progress) can exceed the
/// pipe buffer.
public struct ProcessRunner: Sendable {
    public init() {
        // Writing to a pipe whose reader already exited raises SIGPIPE and
        // kills the writer process by default (verified on this host: exit
        // 141). The only pipe writes this app performs are this runner's
        // stdin deliveries, so ignoring SIGPIPE process-wide (idempotent) is
        // deliberate and safe: the failure becomes a catchable CocoaError
        // that `run` classifies.
        signal(SIGPIPE, SIG_IGN)
    }

    /// Default deadline for a subprocess. tart's quick commands (`--version`,
    /// `list`, `get`) are well under this; long operations use dedicated
    /// streaming runners in later slices.
    public static let defaultTimeout: TimeInterval = 10

    @discardableResult
    public func run(_ executable: String,
                    _ arguments: [String],
                    environment: [String: String] = [:],
                    timeout: TimeInterval = ProcessRunner.defaultTimeout,
                    input: String? = nil,
                    workingDirectory: String? = nil) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessEnvironment.merged(overrides: environment)
        if let workingDirectory {
            // Passed as a raw path string and converted here: tart 2.32.1's
            // control-socket chdir breaks on percent-encoded URL paths, so
            // callers never hand URLs around for working directories.
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe: Pipe?
        if input != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            stdinPipe = pipe
        } else {
            stdinPipe = nil
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.failedToLaunch(executable)
        }

        // Drains start BEFORE the stdin write: a child that emits more than
        // the 64 KB pipe buffer while the parent blocks in `write` cannot
        // deadlock (the readability handlers drain both pipes concurrently).
        let stdoutDrain = Drain(handle: stdoutPipe.fileHandleForReading)
        let stderrDrain = Drain(handle: stderrPipe.fileHandleForReading)
        stdoutDrain.start()
        stderrDrain.start()

        var inputWriteFailed = false
        if let stdinPipe, let input {
            // EPIPE tolerance: with SIGPIPE ignored, a write to
            // a pipe the child already closed throws a catchable CocoaError.
            // A fast-failing child's own exit code + stderr are the truth;
            // only exit-0-with-failed-write is an anomaly (classified below).
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: Data(input.utf8))
            } catch {
                inputWriteFailed = true
            }
            try? stdinPipe.fileHandleForWriting.close()
        }

        let command = ([executable] + arguments).joined(separator: " ")
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            // Give SIGTERM a moment, then force.
            if exited.wait(timeout: .now() + 5) == .timedOut {
                _ = kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
            throw ProcessRunnerError.timedOut(command: command, timeout: timeout)
        }
        if Self.inputDeliveryShouldFail(exitCode: process.terminationStatus,
                                        writeFailed: inputWriteFailed) {
            throw ProcessRunnerError.inputWriteFailed(command: command)
        }
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutDrain.finish(),
            stderr: stderrDrain.finish())
    }

    /// Pure input-delivery classification: a failed stdin write
    /// is a failure only when the child still exits 0 — the credential never
    /// reached tart yet tart claimed success. Any non-zero exit is the
    /// child's own failure and is returned verbatim.
    static func inputDeliveryShouldFail(exitCode: Int32, writeFailed: Bool) -> Bool {
        writeFailed && exitCode == 0
    }

    /// Incrementally drains one pipe: the readability handler appends each
    /// chunk on a serial queue; `finish()` blocks until EOF and returns the
    /// accumulated bytes. One drain per pipe, started before waiting, so the
    /// child can never deadlock on a full pipe buffer. EOF handling is
    /// idempotent: the readability handler can fire again before the queued
    /// cleanup runs, and a duplicate EOF must not underflow the group or
    /// append after the drain is done.
    private final class Drain {
        private let handle: FileHandle
        private let queue = DispatchQueue(label: "TartManager.ProcessRunner.Drain")
        private let ended = DispatchGroup()
        private var data = Data()
        private var didEnd = false

        init(handle: FileHandle) {
            self.handle = handle
        }

        func start() {
            ended.enter()
            handle.readabilityHandler = { [weak self] fileHandle in
                guard let self else { return }
                let chunk = fileHandle.availableData
                self.queue.async {
                    guard !self.didEnd else { return }
                    if chunk.isEmpty {
                        self.didEnd = true
                        self.ended.leave()
                    } else {
                        self.data.append(chunk)
                    }
                }
            }
        }

        /// Blocks until EOF; idempotent.
        func finish() -> String {
            ended.wait()
            return queue.sync { String(decoding: data, as: UTF8.self) }
        }
    }
}
