import Foundation

/// The in-app updater state that the title bar, the menu-bar menu, and the
/// About tab observe. `UpdateController` turns each Sparkle callback into an
/// `UpdateEvent` and applies it here, so every transition is testable
/// without Sparkle. The state is not persisted; Sparkle owns its own
/// preference keys.
public enum UpdateStatus: Equatable, Sendable {
    /// No check has run in this process.
    case idle
    /// A check runs. `userInitiated` is `true` for **Check for Updates**.
    case checking(userInitiated: Bool)
    /// The last check found no newer version (or the user skipped it).
    case upToDate(checkedAt: Date)
    /// A newer version is in the feed.
    case available(version: String)
    /// The user chose to install, and the relaunch waits for running jobs.
    case waitingForJobs(version: String, jobCount: Int)
    /// Sparkle installs the update and relaunches the app.
    case installing(version: String)
    /// The last check failed. `knownVersion` keeps an available version
    /// that a failed background check must not hide.
    case failed(message: String, checkedAt: Date, knownVersion: String?)
    /// The bundle has no updater configuration (`swift run`). Every event
    /// is ignored.
    case unavailable

    /// Returns the state after `event`. Any pair that the state diagram
    /// does not name returns `self`.
    ///
    /// A check that starts while an update is available keeps `.available`.
    /// The title-bar button stays during a background check, and a failure
    /// still knows the version. A user check resumes Sparkle's pending
    /// session, which may not report the update again.
    public func applying(_ event: UpdateEvent) -> UpdateStatus {
        switch (self, event) {
        case (.unavailable, _):
            return self

        case (.available, .checkStarted):
            return self
        case (.idle, .checkStarted(let userInitiated)),
             (.upToDate, .checkStarted(let userInitiated)),
             (.failed, .checkStarted(let userInitiated)):
            return .checking(userInitiated: userInitiated)

        case (.checking, .foundUpdate(let version)),
             (.available, .foundUpdate(let version)):
            return .available(version: version)
        case (.checking, .noUpdate(let date)),
             (.available, .noUpdate(let date)):
            return .upToDate(checkedAt: date)
        // Sparkle also aborts an install it refuses (a bad signature or a
        // bad archive), so a failure leaves `.installing` and
        // `.waitingForJobs` too.
        case (.checking, .checkFailed(let message, let date, _)),
             (.available, .checkFailed(let message, let date, _)),
             (.installing, .checkFailed(let message, let date, _)),
             (.waitingForJobs, .checkFailed(let message, let date, _)):
            return .failed(message: message, checkedAt: date, knownVersion: knownVersion)

        case (.available, .userSkipped):
            return .upToDate(checkedAt: Date())
        case (.available, .userDismissed):
            return self

        // Sparkle reports the install choice before it asks to postpone the
        // relaunch, so a postpone also arrives in `.installing`.
        case (.available(let version), .installPostponed(let jobCount)),
             (.installing(let version), .installPostponed(let jobCount)),
             (.waitingForJobs(let version, _), .installPostponed(let jobCount)):
            return .waitingForJobs(version: version, jobCount: jobCount)
        case (.available(let version), .installStarted),
             (.waitingForJobs(let version, _), .installStarted):
            return .installing(version: version)

        default:
            return self
        }
    }

    /// The newer version this state knows about, or `nil`.
    public var knownVersion: String? {
        switch self {
        case .available(let version),
             .waitingForJobs(let version, _),
             .installing(let version):
            return version
        case .failed(_, _, let version):
            return version
        case .idle, .checking, .upToDate, .unavailable:
            return nil
        }
    }
}

/// An updater event that `UpdateController` makes from a Sparkle callback.
public enum UpdateEvent: Equatable, Sendable {
    case checkStarted(userInitiated: Bool)
    case foundUpdate(version: String)
    case noUpdate(at: Date)
    case checkFailed(message: String, at: Date, userInitiated: Bool)
    case userSkipped(version: String)
    case userDismissed
    case installPostponed(jobCount: Int)
    case installStarted
}
