import Foundation
import Sparkle
import TartKit
import os

/// The only bridge to Sparkle, and the only file that imports it. Each
/// Sparkle callback becomes an `UpdateEvent`, which is applied to the
/// current `UpdateStatus`, logged to `updates`, and published.
///
/// Scheduled checks use gentle reminders: Sparkle opens no window, and the
/// title bar shows the update. A relaunch waits for running jobs through
/// `UpdateInstallGate`.
@MainActor
final class UpdateController: NSObject, AppUpdating, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    private var status: UpdateStatus = .idle
    private var onStatusChange: (@MainActor (UpdateStatus) -> Void)?
    private var activeJobs: @MainActor () -> [JobInfo] = { [] }
    /// Sparkle's relaunch block, saved while the install waits for jobs.
    private var postponedInstall: (() -> Void)?

    private var updater: SPUUpdater? { controller?.updater }

    var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set {
            guard let updater else {
                Logger.updates.notice("automatic checks unchanged: updater unavailable")
                return
            }
            updater.automaticallyChecksForUpdates = newValue
            Logger.updates.info("automatic checks set to \(newValue, privacy: .public)")
        }
    }

    var lastCheckDate: Date? { updater?.lastUpdateCheckDate }

    func start(onStatusChange: @escaping @MainActor (UpdateStatus) -> Void,
               activeJobs: @escaping @MainActor () -> [JobInfo]) {
        self.onStatusChange = onStatusChange
        self.activeJobs = activeJobs
        let missing = UpdaterBundleConfiguration.missingKeys(in: Bundle.main.infoDictionary)
        guard missing.isEmpty else {
            let keys = missing.joined(separator: ", ")
            Logger.updates.notice("updater not started: missing Info.plist keys \(keys, privacy: .public)")
            publish(.unavailable)
            return
        }
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? ""
        Logger.updates.info("updater starting with feed \(feed, privacy: .public)")
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    func checkForUpdates() {
        guard let updater else {
            Logger.updates.notice("check refused: updater unavailable")
            return
        }
        apply(.checkStarted(userInitiated: true))
        updater.checkForUpdates()
    }

    func resumePostponedInstall() {
        guard let install = postponedInstall else {
            Logger.updates.debug("resume skipped: no postponed install")
            return
        }
        switch UpdateInstallGate.decide(activeJobs: activeJobs()) {
        case .installNow:
            postponedInstall = nil
            apply(.installStarted)
            install()
        case .postpone(let jobCount):
            if case .waitingForJobs(_, jobCount) = status {
                Logger.updates.debug("install still waits for \(jobCount, privacy: .public) jobs")
                return
            }
            apply(.installPostponed(jobCount: jobCount))
        }
    }

    // MARK: - State

    private func apply(_ event: UpdateEvent) {
        let next = status.applying(event)
        let line = "event \(String(describing: event)) → \(String(describing: next))"
        Logger.updates.info("\(line, privacy: .public)")
        publish(next)
    }

    private func publish(_ next: UpdateStatus) {
        status = next
        onStatusChange?(next)
    }

    // MARK: - SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard updateCheck == .updatesInBackground else { return }
        if case .checking = status { return }
        apply(.checkStarted(userInitiated: false))
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        apply(.foundUpdate(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        apply(.noUpdate(at: Date()))
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let nsError = error as NSError
        // Sparkle also reports "no update" through this callback;
        // `updaterDidNotFindUpdate(_:)` already handled it.
        if nsError.domain == SUSparkleErrorDomain, nsError.code == Int(SUError.noUpdateError.rawValue) {
            return
        }
        // An aborted install never calls a saved relaunch block.
        postponedInstall = nil
        let userInitiated: Bool
        if case .checking(let initiated) = status {
            userInitiated = initiated
        } else {
            userInitiated = false
        }
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let underlyingText = underlying.map { " underlying=\($0.domain) \($0.code)" } ?? ""
        let line = "update aborted: domain=\(nsError.domain) code=\(nsError.code)"
            + underlyingText + " message=\(nsError.localizedDescription)"
        if Self.isRefusal(nsError) || Self.isRefusal(underlying) || status.isInstallInProgress {
            Logger.updates.error("\(line, privacy: .public)")
        } else {
            Logger.updates.notice("\(line, privacy: .public)")
        }
        apply(.checkFailed(message: nsError.localizedDescription, at: Date(),
                           userInitiated: userInitiated))
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
                 forUpdate updateItem: SUAppcastItem, state: SPUUserUpdateState) {
        switch choice {
        case .skip:
            apply(.userSkipped(version: updateItem.displayVersionString))
        case .dismiss:
            apply(.userDismissed)
        case .install:
            apply(.installStarted)
        @unknown default:
            Logger.updates.notice("unknown update choice \(choice.rawValue, privacy: .public)")
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        switch UpdateInstallGate.decide(activeJobs: activeJobs()) {
        case .installNow:
            Logger.updates.info("relaunching for update \(item.displayVersionString, privacy: .public)")
            return false
        case .postpone(let jobCount):
            postponedInstall = installHandler
            apply(.installPostponed(jobCount: jobCount))
            return true
        }
    }

    /// Signature, archive, and validation failures: Sparkle refused an
    /// update, so the log line is an error. Sparkle can wrap them in an
    /// installation error, so the underlying error counts too.
    private static func isRefusal(_ error: NSError?) -> Bool {
        guard let error, error.domain == SUSparkleErrorDomain else { return false }
        return refusalCodes.contains(error.code)
    }

    private static let refusalCodes: Set<Int> = [
        Int(SUError.signatureError.rawValue),
        Int(SUError.validationError.rawValue),
        Int(SUError.unarchivingError.rawValue),
        Int(SUError.insufficientSigningError.rawValue),
    ]

    // MARK: - SPUStandardUserDriverDelegate

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }
}

private extension UpdateStatus {
    /// An abort in these states is a failed install, not a failed check.
    var isInstallInProgress: Bool {
        switch self {
        case .installing, .waitingForJobs: return true
        default: return false
        }
    }
}
