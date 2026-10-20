import TartKit

/// Which jobs the sidebar "JOBS" section shows, and the icon and
/// accessibility label of the chevron toggle beside the section title.
/// Kept apart from the view so the filter and the collapse rule are tested
/// without rendering.
struct JobListPresentation: Equatable {
    /// The number of rows the collapsed list shows.
    static let collapsedLimit = 2

    /// The rows to render, in job start order.
    let visibleJobs: [JobInfo]
    /// The toggle's accessibility label and help text, or nil when all
    /// listed jobs fit in the collapsed list.
    let toggleLabel: String?
    /// The SF Symbol for the toggle chevron, or nil with no toggle.
    /// The collapsed list shows `^` (expand), the expanded list a down chevron.
    let toggleSymbol: String?

    /// `jobs` is the full `JobManager.jobs` array. Completed and cancelled
    /// jobs are left out at once (`JobRetentionPolicy.isListed`).
    init(jobs: [JobInfo], isExpanded: Bool) {
        let listed = jobs.filter { JobRetentionPolicy.isListed($0.phase) }
        let hidden = listed.count - Self.collapsedLimit
        if hidden <= 0 {
            visibleJobs = listed
            toggleLabel = nil
            toggleSymbol = nil
        } else if isExpanded {
            visibleJobs = listed
            toggleLabel = "Show fewer jobs"
            toggleSymbol = "chevron.down"
        } else {
            visibleJobs = Array(listed.prefix(Self.collapsedLimit))
            toggleLabel = "Show \(hidden) more \(hidden == 1 ? "job" : "jobs")"
            toggleSymbol = "chevron.up"
        }
    }

    /// True when the section has at least one row to show.
    var isEmpty: Bool { visibleJobs.isEmpty }
}
