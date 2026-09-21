import Foundation
import os

/// Keeps Tart clipboard sharing alive across VM restarts: after every
/// app-launched run it re-establishes the tart-guest-agent channel (the
/// documented `launchctl kickstart` workaround) and installs a guest-side
/// LaunchAgent watchdog that repeats the fix after boots and suspend/resumes
/// Tart Manager did not initiate.
///
/// All work is best-effort background hygiene: every skip, degrade, and
/// completion is logged under the `clipboard` category and never presented,
/// because clipboard repair must never block or fail a run. Each `tart`
/// subprocess runs detached at utility priority (the polling class used by
/// `InventoryService`), so the cooperative executor is never pinned.
@MainActor
public final class ClipboardWatchdogCoordinator {
    /// Deadline knobs. Tests inject small values so no real waiting occurs;
    /// production gives a cold macOS boot minutes to answer.
    public struct Configuration: Sendable, Equatable {
        /// How long to wait after a launch for the guest agent to answer
        /// `tart exec` (a macOS cold boot can take minutes).
        public var readinessTimeout: TimeInterval
        /// How long to wait for the agent to answer again after the kick.
        public var recheckTimeout: TimeInterval
        /// Pause between readiness probes.
        public var pollInterval: TimeInterval

        public init(readinessTimeout: TimeInterval = 240,
                    recheckTimeout: TimeInterval = 30,
                    pollInterval: TimeInterval = 3) {
            self.readinessTimeout = readinessTimeout
            self.recheckTimeout = recheckTimeout
            self.pollInterval = pollInterval
        }

        public static let production = Configuration()
    }

    private let configuration: Configuration
    /// Names with an install in flight. Reserved synchronously on the main
    /// actor before any `await`, so a double-run can never spawn two
    /// installs (the same guard discipline as `RunCoordinator.launching`).
    private var inFlight: Set<String> = []

    public init(configuration: Configuration = .production) {
        self.configuration = configuration
    }

    /// Ensures the guest watchdog is installed and the agent link is live
    /// after a launch. Skips (logged) for non-darwin guests and guests whose
    /// agent never becomes ready; every command failure retries on the next
    /// run because `ensureInstalled` is invoked after every launch.
    public func ensureInstalled(name: String, client: TartClient) async {
        guard !inFlight.contains(name) else { return }
        inFlight.insert(name) // synchronous reservation, before any await
        defer { inFlight.remove(name) }

        guard await isDarwinGuest(name, client: client) else {
            let line = "clipboard watchdog skipped for \(name): not a darwin guest or config unavailable"
            Logger.clipboard.info("\(line, privacy: .public)")
            return
        }
        guard await waitUntilReady(name, client: client, timeout: configuration.readinessTimeout) else {
            let line = "clipboard watchdog degraded for \(name): guest agent never answered readiness probes"
            Logger.clipboard.warning("\(line, privacy: .public)")
            return
        }
        _ = await exec(name, command: GuestClipboardWatchdog.agentKickstartCommand, client: client)
        guard await waitUntilReady(name, client: client, timeout: configuration.recheckTimeout) else {
            let line = "clipboard watchdog degraded for \(name): agent did not answer after kickstart"
            Logger.clipboard.warning("\(line, privacy: .public)")
            return
        }
        let installed = await exec(name, command: GuestClipboardWatchdog.installScript(), client: client) != nil
        let outcome = installed ? "installed" : "install command failed; retrying on next run"
        let line = "clipboard watchdog \(outcome) for \(name)"
        Logger.clipboard.info("\(line, privacy: .public)")
    }

    /// True when the VM's configuration reports a darwin guest. A config
    /// read failure reads as "skip": the watchdog is macOS-only and never
    /// justifies surfacing an error for a launch that otherwise succeeded.
    private func isDarwinGuest(_ name: String, client: TartClient) async -> Bool {
        let config = await Task.detached(priority: .utility) {
            try? client.get(name: name)
        }.value
        guard let os = config?.os else { return false }
        return os.lowercased() == "darwin"
    }

    /// Deadline + poll loop around the readiness probe — the same idiom as
    /// `JobManager.awaitIdle`, but with injectable pacing for tests.
    private func waitUntilReady(_ name: String, client: TartClient, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let answer = await exec(name, command: GuestClipboardWatchdog.readinessProbe, client: client),
               answer.contains("ready") {
                return true
            }
            try? await Task.sleep(for: .seconds(configuration.pollInterval))
        }
        return false
    }

    /// One guest command via `tart exec`, off the main actor. `nil` means
    /// the command failed (agent unreachable or non-zero exit).
    private func exec(_ name: String, command: String, client: TartClient) async -> String? {
        await Task.detached(priority: .utility) {
            try? client.exec(name: name, command: command)
        }.value
    }
}
