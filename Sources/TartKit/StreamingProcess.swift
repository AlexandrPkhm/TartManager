import Foundation

/// A running subprocess whose output streams asynchronously via callbacks.
///
/// - Launch failures share `ProcessRunnerError.failedToLaunch` (one
///   definition across all runners) and the env merge reuses
///   `ProcessEnvironment.merged` (finding 7).
/// - `waitForExit()` returns only after the process terminates AND both
///   streams have delivered EOF, so consumers can assert on output
///   immediately (finding 10).
/// - Cancellation sends SIGTERM; when the child ignores it, `waitForExit()`
///   escalates to SIGKILL after `terminationGrace`, so a cancelled job can
///   never stay `.running` forever (finding 9).
public final class StreamingProcess: @unchecked Sendable {
    /// Grace period between SIGTERM and SIGKILL on the cancelled path.
    public static let defaultTerminationGrace: TimeInterval = 5
    /// How long `waitForExit()` waits for both streams to deliver EOF after
    /// termination (far above any realistic pipe drain).
    public static let drainTimeout: TimeInterval = 2

    public let process: Process

    private let terminationGrace: TimeInterval
    private let stateLock = NSLock()
    private var _cancelled = false
    private let output = TextAccumulator()
    private let eofGroup = DispatchGroup()

    init(process: Process, terminationGrace: TimeInterval) {
        self.process = process
        self.terminationGrace = terminationGrace
    }

    public static func launch(
        binaryPath: String,
        arguments: [String],
        environment: [String: String],
        terminationGrace: TimeInterval = StreamingProcess.defaultTerminationGrace,
        onOutput: @escaping @Sendable (String) -> Void
    ) throws -> StreamingProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = arguments
        // Single env-merge implementation shared with ProcessRunner (finding 7).
        process.environment = ProcessEnvironment.merged(overrides: environment)

        let instance = StreamingProcess(process: process, terminationGrace: terminationGrace)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        instance.eofGroup.enter()  // stdout EOF
        instance.eofGroup.enter()  // stderr EOF

        let collect: @Sendable (Data) -> Void = { data in
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            instance.output.append(text)
            onOutput(text)
        }

        // The readability handler delivers data as it arrives; EOF removes it
        // and decrements the drain latch `waitForExit` awaits (finding 10).
        let handler: @Sendable (FileHandle) -> Void = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                instance.eofGroup.leave()
            } else {
                collect(data)
            }
        }
        stdoutPipe.fileHandleForReading.readabilityHandler = handler
        stderrPipe.fileHandleForReading.readabilityHandler = handler
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.failedToLaunch(binaryPath)
        }
        return instance
    }

    /// Blocks until the process terminates and both streams delivered EOF;
    /// returns its termination status. The cancelled path escalates
    /// SIGTERM → SIGKILL after `terminationGrace` (finding 9).
    public func waitForExit() -> Int32 {
        if wasCancelled {
            if process.isRunning {
                let exited = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in exited.signal() }
                if exited.wait(timeout: .now() + terminationGrace) == .timedOut,
                   process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
            }
        } else {
            process.waitUntilExit()
        }
        // Streams close at termination; wait for both EOF deliveries so no
        // output is lost to the readability-handler race (finding 10).
        _ = eofGroup.wait(timeout: .now() + Self.drainTimeout)
        return process.terminationStatus
    }

    /// Terminates the process and marks the job cancelled.
    public func cancel() {
        stateLock.lock()
        _cancelled = true
        stateLock.unlock()
        if process.isRunning {
            process.terminate()
        }
    }

    public var wasCancelled: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _cancelled
    }

    /// Bounded combined output (finding 13): capped at the same budget the
    /// error analyzer applies per stream.
    public var combinedOutput: String { output.value }
}
