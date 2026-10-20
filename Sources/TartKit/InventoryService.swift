import Foundation
import Combine
import os

/// Precondition failure for the inventory fetch: tart is not available
/// (missing/unsatisfied prerequisite) or the storage location is not
/// configured. Distinct from `TartClientError`, which reports genuine tart
/// command failures (Issue 6 normalizes presentation).
public enum InventoryFetchError: Error, Equatable, Sendable {
    case unavailable
}

/// Publishes the VM inventory and keeps it fresh on an interval, diffing each
/// successful snapshot into added/removed/changed deltas.
@MainActor
public final class InventoryService: ObservableObject {
    @Published public private(set) var inventory: VMInventory?
    /// Deltas between the previous successful snapshot and the latest one;
    /// nil until the second successful fetch (the first has no predecessor).
    @Published public private(set) var lastDelta: InventoryDelta?

    /// Called (on the main actor) when a fetch fails. AppModel re-probes
    /// storage availability here, so an unmounted volume flips the UI to the
    /// dedicated unavailable state on the next failed poll (finding 6).
    public var onFetchFailure: (@MainActor (Error) -> Void)?

    /// Poll cadence (PRD: named internal constant, not a user setting).
    nonisolated public static let defaultPollInterval: TimeInterval = 3

    /// How long the whole allocation gather may run before the assessment
    /// degrades to "no warning" (the run proceeds and the expiry is
    /// logged). Each `tart get` inside is separately bounded by the
    /// TartClient's per-run deadline, so a wedged subprocess is
    /// independently capped.
    nonisolated public static let defaultMemoryGatherTimeout: TimeInterval = 5

    /// Coalescing threshold for trigger-driven refreshes (e.g. right after a
    /// successful run): a fetch is skipped when the last successful one is
    /// younger than this, because the 3 s poll is the reconciler of record.
    nonisolated public static let refreshCoalescingInterval: TimeInterval = 1

    /// Timestamp of the last successful fetch; nil until the first one.
    /// Not published: it is an internal coalescing bookkeeping value, and
    /// publishing it would churn `objectWillChange` on every poll.
    public private(set) var lastFetchedAt: Date?

    private var fetch: () throws -> [VMEntry]
    private let pollInterval: TimeInterval
    private let memoryGatherTimeout: TimeInterval
    private var pollTask: Task<Void, Never>?
    private var isFetching = false

    /// True while storage is unavailable. A paused service spawns no fetch:
    /// both the poll and trigger-driven refreshes return at once.
    public private(set) var isPaused = false

    public init(fetch: @escaping () throws -> [VMEntry],
                pollInterval: TimeInterval = InventoryService.defaultPollInterval,
                memoryGatherTimeout: TimeInterval = InventoryService.defaultMemoryGatherTimeout) {
        self.fetch = fetch
        self.pollInterval = pollInterval
        self.memoryGatherTimeout = memoryGatherTimeout
    }

    /// Replaces the fetch closure (AppModel re-wires when settings change).
    public func updateFetch(_ newFetch: @escaping () throws -> [VMEntry]) {
        fetch = newFetch
    }

    /// Fetches once off the main actor and republishes. Concurrent calls are
    /// dropped while a fetch is in flight (bounded by TartClient's timeout,
    /// so a wedged `tart list` degrades to an error, never an unbounded
    /// stall); failures keep the last inventory and report through
    /// `onFetchFailure`.
    public func refresh() async {
        guard !isPaused, !isFetching else { return }
        isFetching = true
        defer { isFetching = false }
        let fetch = self.fetch
        let result = await Task.detached(priority: .utility) { Result { try fetch() } }.value
        switch result {
        case .success(let entries):
            let previous = inventory.map { $0.localVMs + $0.ociImages }
            inventory = VMInventory(from: entries)
            lastDelta = previous.map { InventoryDelta.diff(from: $0, to: entries) }
            lastFetchedAt = Date()
        case .failure(let error):
            onFetchFailure?(error)
        }
    }

    /// Fetches only if the last successful fetch is older than `interval`
    /// (or there was none). Coalesces trigger-driven refreshes with the
    /// poll so redundant subprocesses never stack; any true overlap is
    /// still dropped by `refresh()`'s in-flight guard.
    public func refreshIfStale(
        olderThan interval: TimeInterval = InventoryService.refreshCoalescingInterval
    ) async {
        if let lastFetchedAt, Date().timeIntervalSince(lastFetchedAt) < interval { return }
        await refresh()
    }

    /// Aggregates the memory allocations for the run-time over-commitment
    /// assessment (the inventory service owns allocation aggregation).
    /// Reads the CURRENT inventory snapshot, which is at most one poll
    /// cycle stale and nil before the first poll: a VM started externally
    /// just before the Run click can be missed — documented and logged,
    /// never silently hidden. Every config fetch runs under the client's
    /// per-run deadline; a failed or missing config contributes 0 MB and
    /// is logged (the assessment degrades toward silence, never toward
    /// blocking). The whole gather is raced against `memoryGatherTimeout`;
    /// on expiry the snapshot is nil (logged) and the caller proceeds
    /// ungated.
    public func memoryAllocationSnapshot(
        for targetName: String,
        getConfig: @escaping @Sendable (String) async throws -> VMConfigInfo
    ) async -> MemoryAllocationSnapshot? {
        guard let inventory else {
            Logger.overcommit.warning(
                "no inventory snapshot yet; skipping memory assessment for \(targetName, privacy: .public)")
            return nil
        }
        let ageSeconds = Date().timeIntervalSince(inventory.fetchedAt)
        Logger.overcommit.info(
            "memory assessment for \(targetName, privacy: .public) uses an inventory snapshot \(String(format: "%.1f", ageSeconds)) s old")
        let runningNames = inventory.localVMs
            .filter { $0.running && $0.name != targetName }
            .map(\.name)
        let timeout = memoryGatherTimeout

        let snapshot = await withTaskGroup(of: MemoryAllocationSnapshot?.self) { group in
            group.addTask {
                var runningMB: [Int] = []
                for name in runningNames where !Task.isCancelled {
                    runningMB.append(await Self.memoryMB(for: name, getConfig: getConfig))
                }
                guard !Task.isCancelled else { return nil }
                let targetMB = await Self.memoryMB(for: targetName, getConfig: getConfig)
                return MemoryAllocationSnapshot(runningMB: runningMB, targetMB: targetMB)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }
            let first = await group.next() ?? nil
            // Explicit cancellation: the group scope only waits for
            // remaining tasks on exit, and a wedged config fetch is only
            // bounded by its own deadline — so the loser is always
            // cancelled here, keeping both outcomes fast.
            group.cancelAll()
            return first
        }
        if snapshot == nil {
            Logger.overcommit.warning(
                "memory allocation gather for \(targetName, privacy: .public) exceeded \(timeout) s; the run proceeds without a warning")
        }
        return snapshot
    }

    /// One VM's allocation in MB, or 0 (logged) when the config is missing,
    /// unreadable, or carries no memory value.
    private static func memoryMB(
        for name: String,
        getConfig: @escaping @Sendable (String) async throws -> VMConfigInfo
    ) async -> Int {
        guard let config = try? await getConfig(name),
              let memoryMB = config.memoryMB else {
            Logger.overcommit.warning(
                "no memory allocation for \(name, privacy: .public); counting 0 MB")
            return 0
        }
        return memoryMB
    }

    public func startPolling() {
        stopPolling()
        pollTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(pollInterval))
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Stops fetching until `resume()`. The poll loop keeps its schedule but
    /// skips every fetch, so `startPolling()` order does not matter.
    public func pause() {
        guard !isPaused else { return }
        isPaused = true
        Logger.storage.info("inventory polling paused while storage is unavailable")
    }

    /// Ends a pause. Returns true when the service was paused, so the caller
    /// can fetch at once instead of waiting for the next poll.
    @discardableResult
    public func resume() -> Bool {
        guard isPaused else { return false }
        isPaused = false
        Logger.storage.info("inventory polling resumed")
        return true
    }
}
