import TartKit

/// The UI text and visibility for each `UpdateStatus`. Kept apart from the
/// views so every status maps to tested copy.
struct UpdateStatusCopy: Equatable {
    /// The status line in Settings → About.
    let aboutLine: String
    /// The title-bar button label, or `nil` when the button is hidden.
    let titlebarLabel: String?
    /// Whether the menu-bar menu shows `menuBarItemLabel`.
    let showsMenuBarItem: Bool
    /// Whether **Check for Updates** is enabled.
    let canCheck: Bool

    static let menuBarItemLabel = "Update available…"

    init(status: UpdateStatus) {
        switch status {
        case .idle:
            aboutLine = "Tart Manager has not checked for updates yet."
        case .checking:
            aboutLine = "Checking for updates…"
        case .upToDate:
            aboutLine = "Tart Manager is up to date."
        case .available(let version):
            aboutLine = "Version \(version) is available."
        case .waitingForJobs(let version, let jobCount):
            let jobs = jobCount == 1 ? "1 job finishes" : "\(jobCount) jobs finish"
            aboutLine = "Version \(version) will install when \(jobs)."
        case .installing(let version):
            aboutLine = "Installing version \(version)…"
        case .failed:
            aboutLine = "The last update check failed."
        case .unavailable:
            aboutLine = "Updates are not available in development builds."
        }

        switch status {
        case .available, .failed(_, _, .some):
            // A failure that still knows a newer version keeps it visible.
            titlebarLabel = "Update Available"
        case .waitingForJobs(_, let jobCount):
            titlebarLabel = jobCount == 1 ? "Update waits for 1 job" : "Update waits for \(jobCount) jobs"
        default:
            titlebarLabel = nil
        }
        showsMenuBarItem = titlebarLabel != nil

        switch status {
        case .checking, .installing, .unavailable:
            canCheck = false
        default:
            canCheck = true
        }
    }
}
