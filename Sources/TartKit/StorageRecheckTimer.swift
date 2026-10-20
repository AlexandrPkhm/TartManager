import Foundation

/// Re-runs a storage availability probe on a slow, fixed interval while the
/// configured storage is unavailable. It replaces the 3 s inventory poll in
/// that state, so an unmounted volume costs one cheap `stat` per interval
/// instead of one `tart list` subprocess per poll.
@MainActor
public final class StorageRecheckTimer {
    /// Recheck cadence while storage is unavailable. Slow on purpose: the
    /// Retry button and window focus give an immediate check.
    nonisolated public static let defaultInterval: TimeInterval = 30

    private let interval: TimeInterval
    private var task: Task<Void, Never>?

    public var isRunning: Bool { task != nil }

    public init(interval: TimeInterval = StorageRecheckTimer.defaultInterval) {
        self.interval = interval
    }

    /// Calls `tick` once per interval until `stop()`. A second call while
    /// running keeps the current schedule.
    public func start(_ tick: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        task = Task { [interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                tick()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
