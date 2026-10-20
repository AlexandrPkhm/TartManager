import Foundation
import TartKit

/// The updater surface `AppModel` uses. `UpdateController` implements it
/// with Sparkle; tests inject a fake, so no test starts Sparkle.
@MainActor
protocol AppUpdating: AnyObject {
    /// Daily background checks. Sparkle persists the choice.
    var automaticallyChecksForUpdates: Bool { get set }
    /// The time of the last completed check, or `nil` before the first one.
    var lastCheckDate: Date? { get }

    /// Starts the updater. `onStatusChange` receives every new status, and
    /// `activeJobs` supplies the jobs that can postpone a relaunch.
    func start(onStatusChange: @escaping @MainActor (UpdateStatus) -> Void,
               activeJobs: @escaping @MainActor () -> [JobInfo])
    /// A user-initiated check. Sparkle shows its window for the result.
    func checkForUpdates()
    /// Re-runs the install gate for a postponed relaunch: installs now when
    /// no job runs, or reports the new job count.
    func resumePostponedInstall()
}
