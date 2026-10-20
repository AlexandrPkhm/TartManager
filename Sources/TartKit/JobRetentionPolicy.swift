import Foundation

/// Decides which jobs the job list shows and when `JobManager` releases
/// finished job records.
///
/// The list shows running jobs and failed jobs. A completed or cancelled job
/// needs no action, so it leaves the list at once. A failed job stays until
/// the person dismisses it, because its row is the only way back to the
/// error report.
public enum JobRetentionPolicy {
    /// How long `JobManager` keeps a completed or cancelled record after
    /// its terminal transition. Observers and tests can read the outcome
    /// during this time. Then the record is released, so a long-lived
    /// process does not collect finished jobs.
    public static let releaseDelay: Duration = .seconds(4)

    /// True when the job list shows a job in `phase`.
    public static func isListed(_ phase: JobInfo.Phase) -> Bool {
        switch phase {
        case .running, .failed: return true
        case .completed, .cancelled: return false
        }
    }

    /// True when `JobManager` releases a job in `phase` after
    /// `releaseDelay`, with no dismiss action.
    public static func releasesAutomatically(_ phase: JobInfo.Phase) -> Bool {
        !isListed(phase)
    }
}
