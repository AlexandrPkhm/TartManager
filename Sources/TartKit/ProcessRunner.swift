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
}

/// Runs a subprocess and captures its exit code, stdout, and stderr.
///
/// stdout and stderr are drained concurrently so a child that fills one pipe
/// (the OS pipe buffer is 64 KB) cannot deadlock the run; a timeout terminates
/// children that never exit. This runner is the foundation for all later
/// slices, whose output (`list --format json`, clone progress) can exceed the
/// pipe buffer.
public struct ProcessRunner: Sendable {
    public init() {}

    /// Default deadline for a subprocess. tart's quick commands (`--version`,
    /// `list`, `get`) are well under this; long operations use dedicated
    /// streaming runners in later slices.
    public static let defaultTimeout: TimeInterval = 10

    @discardableResult
    public func run(_ executable: String,
                    _ arguments: [String],
                    environment: [String: String] = [:],
                    timeout: TimeInterval = ProcessRunner.defaultTimeout) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in environment { env[key] = value }
            process.environment = env
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.failedToLaunch(executable)
        }

        let stdoutDrain = Drain(handle: stdoutPipe.fileHandleForReading)
        let stderrDrain = Drain(handle: stderrPipe.fileHandleForReading)
        stdoutDrain.start()
        stderrDrain.start()

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
        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutDrain.finish(),
            stderr: stderrDrain.finish())
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
