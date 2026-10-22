/// Decides whether the tart source (or the custom path) can change now.
///
/// A running job holds a client built from the current binary, so a switch
/// waits until no job runs. VMs run as detached processes and do not block
/// it: a later `tart stop` from the new binary uses the same `TART_HOME`.
public enum TartSourceSwitchGate {
    public enum Decision: Equatable, Sendable {
        case allow
        case refuse(jobCount: Int)
    }

    /// Only `.running` jobs refuse the switch. Completed, failed, and
    /// cancelled jobs stay in the list but do not count.
    public static func decide(activeJobs: [JobInfo]) -> Decision {
        let running = activeJobs.filter { $0.phase == .running }.count
        return running == 0 ? .allow : .refuse(jobCount: running)
    }

    /// The refusal copy, shared by the presented error and the Settings caption.
    public static func refusalMessage(jobCount: Int) -> String {
        let jobs = jobCount == 1 ? "1 running job" : "\(jobCount) running jobs"
        return "Finish or cancel \(jobs) to change the tart source."
    }
}
