import Foundation

/// Pure automatic-pruning eligibility; failed attempts count toward the
/// daily limit, and clock rollback never causes an immediate retry.
public enum CachePruneSchedule {
    /// Minimum interval between automatic attempts, in seconds.
    public static let interval: TimeInterval = 86_400

    /// Manual never schedules; automatic policies run at most once daily.
    public static func isDue(policy: CachePrunePolicy, lastAttempt: Date?, now: Date) -> Bool {
        guard policy != .manual else { return false }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval
    }
}
