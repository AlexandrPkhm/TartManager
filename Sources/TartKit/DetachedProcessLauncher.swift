import Foundation

/// Configuration for one detached (long-lived) launch.
public struct DetachedLaunchConfiguration: Sendable {
    /// Shared early-failure-window default: the single source of the 5 s
    /// literal, used by this initializer and by `TartClient.runVM`.
    public static let defaultEarlyFailureWindow: TimeInterval = 5

    public let binaryPath: String
    public let arguments: [String]
    public let environment: [String: String]
    public let earlyFailureWindow: TimeInterval
    /// Where the run log is created; injectable so tests stay isolated.
    public let logDirectory: URL
    /// Working directory for the child as a raw path string. tart 2.32.1
    /// binds its per-VM control socket relative to the run process's cwd
    /// whenever its own chdir into the VM directory fails on a
    /// percent-encoded storage path; launching with this set to the VM's
    /// directory keeps the socket in its intended place. Nil keeps the
    /// parent's cwd.
    public let workingDirectory: String?

    public init(binaryPath: String,
                arguments: [String],
                environment: [String: String],
                earlyFailureWindow: TimeInterval = DetachedLaunchConfiguration.defaultEarlyFailureWindow,
                logDirectory: URL = FileManager.default.temporaryDirectory,
                workingDirectory: String? = nil) {
        self.binaryPath = binaryPath
        self.arguments = arguments
        self.environment = environment
        self.earlyFailureWindow = earlyFailureWindow
        self.logDirectory = logDirectory
        self.workingDirectory = workingDirectory
    }
}

/// Failures of a detached launch.
public enum DetachedLauncherError: Error, Equatable {
    case failedToLaunch(String)
    case exitedQuickly(exitCode: Int32, output: String)
}

/// A running child the app does not own the lifetime of.
public final class DetachedProcessHandle: @unchecked Sendable {
    public let process: Process
    public let pid: Int32
    /// Temp file that held the child's early output; unlinked as soon as
    /// the early window passes (success) or before throwing (failure).
    public let logURL: URL

    init(process: Process, logURL: URL) {
        self.process = process
        self.pid = process.processIdentifier
        self.logURL = logURL
    }

    public var isRunning: Bool { process.isRunning }
}

extension DetachedProcessHandle: Equatable {
    public static func == (lhs: DetachedProcessHandle, rhs: DetachedProcessHandle) -> Bool {
        lhs === rhs
    }
}

/// Launches long-lived children that outlive the app.
///
/// The child's stdout+stderr go to a temporary file (never a `Pipe`),
/// so the child never depends on the parent's file descriptors and
/// survives app termination without SIGPIPE hazards. The log file is
/// removed on every terminal path: before throwing `failedToLaunch` /
/// `exitedQuickly`, and — on success — unlinked the moment the early
/// window elapses. The running child keeps writing to the unlinked
/// inode (POSIX), whose disk space is reclaimed when the child exits,
/// so no file accumulates in the temp directory while a VM runs.
public final class DetachedProcessLauncher: @unchecked Sendable {
    /// Run-log filename prefix; `RunCoordinator.cleanupStaleLogs` sweeps it.
    public static let logFilePrefix = "tartmanager-run-"

    public init() {}

    public func launch(_ configuration: DetachedLaunchConfiguration) throws -> DetachedProcessHandle {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: configuration.binaryPath)
        process.arguments = configuration.arguments
        process.environment = ProcessEnvironment.merged(overrides: configuration.environment)
        if let workingDirectory = configuration.workingDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        }

        let logURL = configuration.logDirectory
            .appendingPathComponent("\(Self.logFilePrefix)\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
            throw DetachedLauncherError.failedToLaunch(configuration.binaryPath)
        }
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
        } catch {
            try? logHandle.close()
            try? FileManager.default.removeItem(at: logURL)
            throw DetachedLauncherError.failedToLaunch(configuration.binaryPath)
        }
        // The child owns its inherited descriptors now; drop our write end.
        try? logHandle.close()

        // Early-failure window: fail fast if the child dies immediately.
        let deadline = Date().addingTimeInterval(configuration.earlyFailureWindow)
        while Date() < deadline {
            if !process.isRunning {
                let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                try? FileManager.default.removeItem(at: logURL)
                throw DetachedLauncherError.exitedQuickly(
                    exitCode: process.terminationStatus, output: output)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        // Success: the output was only needed for the window. Unlink now so
        // the child's further writes go to an unlinked inode reclaimed at
        // exit — bounded namespace and bounded disk for arbitrarily long runs.
        try? FileManager.default.removeItem(at: logURL)
        return DetachedProcessHandle(process: process, logURL: logURL)
    }
}
