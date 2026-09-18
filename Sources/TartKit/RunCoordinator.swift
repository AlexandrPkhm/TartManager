import Foundation

/// Orchestrates detached VM runs: a race-safe double-launch guard plus a
/// registry that is evicted when a run ends. Lives in TartKit so every
/// guard, reservation, and eviction rule carries unit tests; `AppModel`
/// stays thin plumbing.
@MainActor
public final class RunCoordinator {
    public enum Outcome: Equatable {
        case started(DetachedProcessHandle)
        case alreadyLaunching(name: String)
        /// `cause` is the raw client failure for the standardized error
        /// report; `message` is the legacy presentation text, kept for its
        /// existing tests and logging.
        case failed(name: String, message: String, cause: TartClientError)
    }

    /// Names with a launch in flight. Reserved synchronously on the main
    /// actor before any `await`, so a fast double-run can never spawn two
    /// `tart run` processes.
    private var launching: Set<String> = []
    /// Successfully started handles keyed by VM name.
    private var running: [String: DetachedProcessHandle] = [:]

    public init() {}

    /// True when a live launch (in flight or started) owns `name`.
    public func isRegistered(_ name: String) -> Bool {
        launching.contains(name) || running[name] != nil
    }

    /// Launches `name` through the client. The name is reserved before the
    /// spawn; concurrent calls for the same name return `.alreadyLaunching`.
    /// A failed launch releases the reservation; a successful one registers
    /// the handle until `reconcile` evicts it. Saved shared folders are
    /// forwarded to the client so every app-launched run carries them.
    public func launch(
        name: String,
        using client: TartClient,
        shares: [VMFolderShare] = [],
        earlyFailureWindow: TimeInterval = DetachedLaunchConfiguration.defaultEarlyFailureWindow,
        logDirectory: URL = FileManager.default.temporaryDirectory
    ) async -> Outcome {
        if let dead = running[name], !dead.isRunning {
            running.removeValue(forKey: name) // child exited; free the name
        }
        guard !isRegistered(name) else { return .alreadyLaunching(name: name) }
        launching.insert(name) // synchronous reservation, before any await
        let result = await Task.detached(priority: .userInitiated) {
            Result { try client.runVM(
                name: name,
                shares: shares,
                earlyFailureWindow: earlyFailureWindow,
                logDirectory: logDirectory) }
        }.value
        switch result {
        case .success(let handle):
            launching.remove(name)
            running[name] = handle
            return .started(handle)
        case .failure(let error):
            launching.remove(name)
            let cause = error as? TartClientError
                ?? TartClientError.commandFailed(command: "run", exitCode: -1, stdout: "", stderr: "\(error)")
            return .failed(name: name, message: Self.message(for: error, name: name), cause: cause)
        }
    }

    /// Evicts registered entries whose child exited on its own or whose VM
    /// the inventory reports as stopped. `AppModel` calls this on every
    /// inventory change, so run → stop → run works for the app's lifetime.
    public func reconcile(with entries: [VMEntry]) {
        for (name, handle) in running {
            let stoppedPerInventory = entries.first { $0.name == name }
                .map { !$0.running } ?? false
            if !handle.isRunning || stoppedPerInventory {
                running.removeValue(forKey: name)
            }
        }
    }

    /// Deterministically evicts the registry entry for `name`: the VM left
    /// the running state (suspend, stop, window close) so its run handle is
    /// stale — a Resume click must not be blocked by the registry while
    /// waiting for the next poll's `reconcile` eviction. No-op when the
    /// name is not registered. Safe against in-flight launches: the
    /// `launching` reservation is held only while spawning a VM the
    /// inventory does not yet report as running, which suspend/stop never
    /// target.
    public func release(name: String) {
        running.removeValue(forKey: name)
    }

    /// User-facing failure text built from the raw CLI error; asserted
    /// exactly in `RunCoordinatorTests` (the standardized alert arrives
    /// with the error-reporting slice).
    static func message(for error: Error, name: String) -> String {
        if let tartError = error as? TartClientError,
           case .commandFailed(_, let exitCode, _, let stderr) = tartError {
            let detail = stderr.isEmpty ? "tart exited with code \(exitCode)." : stderr
            return "Couldn't run \(name):\n\(detail)"
        }
        return "Couldn't run \(name): \(error)"
    }

    /// Removes leftover detached-run logs — files created by a launch whose
    /// early window never completed (the app was killed mid-launch). Live
    /// runs unlink their logs as soon as the window passes, so this sweep
    /// exists for app starts after a crash. Removes regular files only.
    public static func cleanupStaleLogs(
        in directory: URL = FileManager.default.temporaryDirectory
    ) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for url in files where url.lastPathComponent.hasPrefix(DetachedProcessLauncher.logFilePrefix) {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
