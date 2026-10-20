/// Decides whether the app can relaunch for an update now. A relaunch ends
/// every `JobManager` child process, so a running job postpones it. VMs run
/// as detached processes and do not block it.
public enum UpdateInstallGate {
    public enum Decision: Equatable, Sendable {
        case installNow
        case postpone(jobCount: Int)
    }

    /// Only `.running` jobs block the install. Completed, failed, and
    /// cancelled jobs stay in the list but do not count.
    public static func decide(activeJobs: [JobInfo]) -> Decision {
        let running = activeJobs.filter { $0.phase == .running }.count
        return running == 0 ? .installNow : .postpone(jobCount: running)
    }
}
