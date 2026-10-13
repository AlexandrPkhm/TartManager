import Foundation
import os

/// Coordinates explicit and daily cache maintenance through the existing
/// cancellable Jobs pipeline. Readiness gates are synchronous, and cache
/// mutation is deferred while another heavy job owns storage resources.
@MainActor
public final class CachePruneCoordinator {
    private let settings: AppSettings
    private let jobManager: JobManager
    private let makeClient: () -> TartClient?
    private let isStorageAvailable: () -> Bool
    private let now: () -> Date
    private var timer: Task<Void, Never>?

    /// Visible normalized feedback for refused explicit cleanup. Automatic
    /// deferrals are logged; job failures use JobManager's standard callback.
    public var onRefusal: ((TartOperationError) -> Void)?

    /// The supplied client must inject the currently configured TART_HOME;
    /// the coordinator never falls back to a shell or default storage path.
    public init(settings: AppSettings, jobManager: JobManager,
                makeClient: @escaping () -> TartClient?,
                isStorageAvailable: @escaping () -> Bool,
                now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.jobManager = jobManager
        self.makeClient = makeClient
        self.isStorageAvailable = isStorageAvailable
        self.now = now
    }

    deinit { timer?.cancel() }

    /// Starts app-lifetime maintenance once: checks immediately and daily.
    /// Weak capture releases the coordinator while the timer is sleeping.
    public func startAutomaticPruning() {
        guard timer == nil else { return }
        checkAutomaticPruning()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(CachePruneSchedule.interval)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.checkAutomaticPruning()
            }
        }
    }

    /// Rechecks due maintenance after readiness changes or jobs become idle.
    /// Attempt timestamps change only after JobManager accepts a start.
    public func checkAutomaticPruning() {
        let policy = settings.cachePrunePolicy
        guard policy != .manual else { return }
        let date = now()
        guard let path = settings.storagePath else {
            refuse("Automatic cache pruning deferred: no storage location is configured.", manual: false)
            return
        }
        guard CachePruneSchedule.isDue(
            policy: policy, lastAttempt: settings.lastAutomaticPruneAttempt(forStoragePath: path),
            now: date) else { return }
        guard let (client, home) = readyClient(manual: false) else { return }
        if case .started = startJob(policy: policy, client: client, home: home, priority: .utility) {
            settings.recordAutomaticPruneAttempt(at: date, forStoragePath: path)
        } else {
            refuse("Automatic cache pruning deferred: cache cleanup is already running.", manual: false)
        }
    }

    /// Explicit cleanup stays available in Manual mode and never consumes
    /// the automatic attempt timestamp. Manual mode prunes caches of all ages.
    public func startManualPruning(policy: CachePrunePolicy) {
        guard let (client, home) = readyClient(manual: true) else { return }
        if case .duplicateTarget = startJob(policy: policy, client: client, home: home, priority: .userInitiated) {
            refuse("Cache cleanup is already running. Wait for it to finish before trying again.", manual: true)
        }
    }

    private func readyClient(manual: Bool) -> (TartClient, String)? {
        guard isStorageAvailable() else {
            refuse("Cache cleanup cannot start because VM storage is unavailable.", manual: manual)
            return nil
        }
        guard jobManager.runningTargets.isEmpty else {
            refuse("Cache cleanup is deferred while another job is running. Wait for it to finish before trying again.",
                   manual: manual)
            return nil
        }
        guard let client = makeClient() else {
            refuse("Cache cleanup cannot start because tart is unavailable.", manual: manual)
            return nil
        }
        guard let home = client.environment["TART_HOME"], !home.isEmpty,
              home.hasPrefix("/"), let configuredPath = settings.storagePath,
              URL(fileURLWithPath: home).standardizedFileURL.path ==
                URL(fileURLWithPath: configuredPath).standardizedFileURL.path else {
            refuse("Cache cleanup cannot start because the configured VM storage does not match TART_HOME.",
                   manual: manual)
            return nil
        }
        return (client, home)
    }

    private func startJob(policy: CachePrunePolicy, client: TartClient,
                          home: String, priority: TaskPriority) -> JobManager.StartResult {
        jobManager.start(kind: .prune, priority: priority) { context in
            guard !context.isCancelled else { return }
            let freeBefore = DiskSpace.freeBytes(atPath: home)
            context.report(PullProgress(fraction: nil, note: "pruning…"))
            let outcome = try client.prune(
                olderThanDays: policy.retentionDays,
                onOutput: { _ in },
                registerCancel: { action in
                    context.registerCancel(action)
                    if context.isCancelled { action() }
                })
            guard outcome != .cancelled, !context.isCancelled else { return }
            context.reportSummary(PruneSummary.compose(
                freeBefore: freeBefore, freeAfter: DiskSpace.freeBytes(atPath: home)))
        }
    }

    private func refuse(_ message: String, manual: Bool) {
        Logger.storage.info("\(message, privacy: .public)")
        if manual {
            onRefusal?(TartClientError.commandFailed(
                command: "prune", exitCode: -1, stdout: "", stderr: message).normalized)
        }
    }
}
