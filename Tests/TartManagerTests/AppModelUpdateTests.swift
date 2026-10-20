import Testing
import Foundation
@testable import TartKit
@testable import TartManager

/// Records every `AppUpdating` call and exposes the callbacks that
/// `AppModel` passes to `start`, so tests drive the status without Sparkle.
@MainActor
final class FakeUpdater: AppUpdating {
    var automaticallyChecksForUpdates = true
    var lastCheckDate: Date?
    private(set) var startCount = 0
    private(set) var checkCount = 0
    private(set) var resumeCount = 0
    /// The job phases `activeJobs` returned at each resume call.
    private(set) var phasesAtResume: [[JobInfo.Phase]] = []
    private(set) var onStatusChange: (@MainActor (UpdateStatus) -> Void)?
    private(set) var activeJobs: (@MainActor () -> [JobInfo])?

    func start(onStatusChange: @escaping @MainActor (UpdateStatus) -> Void,
               activeJobs: @escaping @MainActor () -> [JobInfo]) {
        startCount += 1
        self.onStatusChange = onStatusChange
        self.activeJobs = activeJobs
    }

    func checkForUpdates() { checkCount += 1 }
    func resumePostponedInstall() {
        resumeCount += 1
        phasesAtResume.append(activeJobs?().map(\.phase) ?? [])
    }

    func send(_ status: UpdateStatus) { onStatusChange?(status) }
}

@Suite @MainActor struct AppModelUpdateTests {
    private func makeModel() -> (AppModel, FakeUpdater) {
        let suite = "AppModelUpdateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let updater = FakeUpdater()
        let model = AppModel(settings: AppSettings(defaults: defaults), updater: updater)
        return (model, updater)
    }

    /// Runs one prune job with an immediate body to completion, then lets
    /// the main queue deliver the deferred job-list observation.
    private func runImmediateJob(on model: AppModel) async {
        model.jobManager.start(kind: .prune, body: { _ in })
        await model.jobManager.awaitIdle(timeout: 10)
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test func initStartsUpdaterOnce() {
        let (_, updater) = makeModel()
        #expect(updater.startCount == 1)
    }

    @Test func showAboutSelectsAboutTab() {
        let (model, _) = makeModel()
        #expect(model.selectedSettingsTab == .general)
        model.showAbout()
        #expect(model.selectedSettingsTab == .about)
    }

    @Test func statusCallbackPublishesStatus() {
        let (model, updater) = makeModel()
        #expect(model.updateStatus == .idle)
        updater.send(.available(version: "1.3.0"))
        #expect(model.updateStatus == .available(version: "1.3.0"))
    }

    @Test func checkForUpdatesForwards() {
        let (model, updater) = makeModel()
        model.checkForUpdates()
        #expect(updater.checkCount == 1)
    }

    @Test func automaticChecksToggleForwards() {
        let (model, updater) = makeModel()
        model.automaticUpdateChecks = false
        #expect(updater.automaticallyChecksForUpdates == false)
        updater.automaticallyChecksForUpdates = true
        #expect(model.automaticUpdateChecks == true)
    }

    @Test func lastUpdateCheckReadsUpdater() {
        let (model, updater) = makeModel()
        #expect(model.lastUpdateCheck == nil)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        updater.lastCheckDate = date
        #expect(model.lastUpdateCheck == date)
    }

    @Test func jobChangeWhileWaitingRequestsResume() async {
        let (model, updater) = makeModel()
        updater.send(.waitingForJobs(version: "1.3.0", jobCount: 1))
        await runImmediateJob(on: model)
        #expect(updater.resumeCount >= 1)
    }

    @Test func jobChangeWhileNotWaitingDoesNothing() async {
        let (model, updater) = makeModel()
        updater.send(.available(version: "1.3.0"))
        await runImmediateJob(on: model)
        #expect(updater.resumeCount == 0)
    }

    /// `@Published` emits before it stores the new value. The resume must
    /// see the finished job list, or the gate would postpone forever.
    @Test func resumeSeesFinishedJobList() async {
        let (model, updater) = makeModel()
        updater.send(.waitingForJobs(version: "1.3.0", jobCount: 1))
        await runImmediateJob(on: model)
        #expect(updater.phasesAtResume.last == [.completed])
    }

    @Test func activeJobsSourceReadsJobManager() async {
        let (model, updater) = makeModel()
        #expect(updater.activeJobs?().isEmpty == true)
        await runImmediateJob(on: model)
        #expect(updater.activeJobs?() == model.jobManager.jobs)
        #expect(updater.activeJobs?().count == 1)
    }
}
