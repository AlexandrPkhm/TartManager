import Foundation
import Testing
@testable import TartKit

@Suite struct UpdateStatusTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func checkStartedFromIdleIsChecking() {
        let next = UpdateStatus.idle.applying(.checkStarted(userInitiated: false))
        #expect(next == .checking(userInitiated: false))
    }

    @Test func checkStartedFromSettledStatesIsChecking() {
        let settled: [UpdateStatus] = [
            .upToDate(checkedAt: date),
            .failed(message: "offline", checkedAt: date, knownVersion: nil),
        ]
        for status in settled {
            #expect(status.applying(.checkStarted(userInitiated: true)) == .checking(userInitiated: true))
        }
    }

    /// Sparkle resumes a pending update session on a user check and may
    /// not report the update again, so `.available` must not move to
    /// `.checking`.
    @Test func checkStartedWhileAvailableKeepsAvailable() {
        let status = UpdateStatus.available(version: "1.3.0")
        #expect(status.applying(.checkStarted(userInitiated: true)) == status)
        #expect(status.applying(.checkStarted(userInitiated: false)) == status)
    }

    @Test func foundUpdateIsAvailable() {
        let next = UpdateStatus.checking(userInitiated: false).applying(.foundUpdate(version: "1.3.0"))
        #expect(next == .available(version: "1.3.0"))
    }

    @Test func noUpdateIsUpToDate() {
        let next = UpdateStatus.checking(userInitiated: true).applying(.noUpdate(at: date))
        #expect(next == .upToDate(checkedAt: date))
    }

    @Test func checkFailureKeepsKnownVersion() {
        let next = UpdateStatus.available(version: "1.3.0")
            .applying(.checkStarted(userInitiated: false))
            .applying(.checkFailed(message: "offline", at: date, userInitiated: false))
        #expect(next == .failed(message: "offline", checkedAt: date, knownVersion: "1.3.0"))
    }

    @Test func checkFailureWithoutKnownVersion() {
        let next = UpdateStatus.checking(userInitiated: true)
            .applying(.checkFailed(message: "offline", at: date, userInitiated: true))
        #expect(next == .failed(message: "offline", checkedAt: date, knownVersion: nil))
    }

    /// Sparkle aborts an install it refuses (bad signature, bad archive).
    /// The status must leave `.installing`, or the UI waits forever.
    @Test func installFailureKeepsKnownVersion() {
        let installing = UpdateStatus.installing(version: "1.3.0")
            .applying(.checkFailed(message: "bad archive", at: date, userInitiated: false))
        #expect(installing == .failed(message: "bad archive", checkedAt: date, knownVersion: "1.3.0"))
        let waiting = UpdateStatus.waitingForJobs(version: "1.3.0", jobCount: 1)
            .applying(.checkFailed(message: "bad archive", at: date, userInitiated: false))
        #expect(waiting == .failed(message: "bad archive", checkedAt: date, knownVersion: "1.3.0"))
    }

    @Test func skipReturnsToUpToDate() {
        let next = UpdateStatus.available(version: "1.3.0").applying(.userSkipped(version: "1.3.0"))
        guard case .upToDate = next else {
            Issue.record("expected upToDate, got \(next)")
            return
        }
    }

    @Test func dismissKeepsAvailable() {
        let status = UpdateStatus.available(version: "1.3.0")
        #expect(status.applying(.userDismissed) == status)
    }

    @Test func postponeWaitsForJobs() {
        let next = UpdateStatus.available(version: "1.3.0").applying(.installPostponed(jobCount: 2))
        #expect(next == .waitingForJobs(version: "1.3.0", jobCount: 2))
    }

    @Test func postponeUpdatesJobCount() {
        let next = UpdateStatus.waitingForJobs(version: "1.3.0", jobCount: 2)
            .applying(.installPostponed(jobCount: 1))
        #expect(next == .waitingForJobs(version: "1.3.0", jobCount: 1))
    }

    /// Sparkle reports the user's install choice before it asks to
    /// postpone the relaunch, so a postpone arrives in `.installing`.
    @Test func postponeFromInstallingWaitsForJobs() {
        let next = UpdateStatus.available(version: "1.3.0")
            .applying(.installStarted)
            .applying(.installPostponed(jobCount: 1))
        #expect(next == .waitingForJobs(version: "1.3.0", jobCount: 1))
    }

    @Test func installStartsFromAvailableAndWaiting() {
        #expect(UpdateStatus.available(version: "1.3.0").applying(.installStarted)
            == .installing(version: "1.3.0"))
        #expect(UpdateStatus.waitingForJobs(version: "1.3.0", jobCount: 1).applying(.installStarted)
            == .installing(version: "1.3.0"))
    }

    @Test func unrelatedEventsKeepStatus() {
        #expect(UpdateStatus.idle.applying(.installStarted) == .idle)
        #expect(UpdateStatus.idle.applying(.foundUpdate(version: "1.3.0")) == .idle)
        #expect(UpdateStatus.upToDate(checkedAt: date).applying(.installPostponed(jobCount: 1))
            == .upToDate(checkedAt: date))
    }

    @Test func unavailableIgnoresEvents() {
        let events: [UpdateEvent] = [
            .checkStarted(userInitiated: true),
            .foundUpdate(version: "1.3.0"),
            .noUpdate(at: date),
            .checkFailed(message: "x", at: date, userInitiated: false),
            .userSkipped(version: "1.3.0"),
            .userDismissed,
            .installPostponed(jobCount: 1),
            .installStarted,
        ]
        for event in events {
            #expect(UpdateStatus.unavailable.applying(event) == .unavailable)
        }
    }

    @Test func knownVersionReadsAvailableWaitingAndFailed() {
        #expect(UpdateStatus.available(version: "1.3.0").knownVersion == "1.3.0")
        #expect(UpdateStatus.waitingForJobs(version: "1.3.0", jobCount: 1).knownVersion == "1.3.0")
        #expect(UpdateStatus.installing(version: "1.3.0").knownVersion == "1.3.0")
        #expect(UpdateStatus.failed(message: "x", checkedAt: date, knownVersion: "1.3.0").knownVersion == "1.3.0")
        #expect(UpdateStatus.failed(message: "x", checkedAt: date, knownVersion: nil).knownVersion == nil)
        #expect(UpdateStatus.idle.knownVersion == nil)
        #expect(UpdateStatus.checking(userInitiated: false).knownVersion == nil)
        #expect(UpdateStatus.upToDate(checkedAt: date).knownVersion == nil)
        #expect(UpdateStatus.unavailable.knownVersion == nil)
    }
}
