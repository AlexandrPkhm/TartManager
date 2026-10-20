import Foundation
import Testing
@testable import TartKit
@testable import TartManager

@Suite struct UpdateStatusCopyTests {
    private static let date = Date(timeIntervalSince1970: 1_800_000_000)

    /// One status of every case, for the properties that every case sets.
    private static let everyStatus: [UpdateStatus] = [
        .idle,
        .checking(userInitiated: false),
        .upToDate(checkedAt: date),
        .available(version: "1.3.0"),
        .waitingForJobs(version: "1.3.0", jobCount: 2),
        .installing(version: "1.3.0"),
        .failed(message: "offline", checkedAt: date, knownVersion: nil),
        .unavailable,
    ]

    @Test func aboutLineForEveryStatus() {
        let lines = Self.everyStatus.map { UpdateStatusCopy(status: $0).aboutLine }
        #expect(lines == [
            "Tart Manager has not checked for updates yet.",
            "Checking for updates…",
            "Tart Manager is up to date.",
            "Version 1.3.0 is available.",
            "Version 1.3.0 will install when 2 jobs finish.",
            "Installing version 1.3.0…",
            "The last update check failed.",
            "Updates are not available in development builds.",
        ])
    }

    @Test func userInitiatedCheckingUsesTheSameLine() {
        #expect(UpdateStatusCopy(status: .checking(userInitiated: true)).aboutLine
            == "Checking for updates…")
    }

    @Test func waitingLineUsesSingularAndPlural() {
        #expect(UpdateStatusCopy(status: .waitingForJobs(version: "1.3.0", jobCount: 1)).aboutLine
            == "Version 1.3.0 will install when 1 job finishes.")
        #expect(UpdateStatusCopy(status: .waitingForJobs(version: "1.3.0", jobCount: 3)).aboutLine
            == "Version 1.3.0 will install when 3 jobs finish.")
    }

    @Test func titlebarLabelOnlyForAvailableAndWaiting() {
        #expect(UpdateStatusCopy(status: .available(version: "1.3.0")).titlebarLabel
            == "Update Available")
        #expect(UpdateStatusCopy(status: .waitingForJobs(version: "1.3.0", jobCount: 1)).titlebarLabel
            == "Update waits for 1 job")
        #expect(UpdateStatusCopy(status: .waitingForJobs(version: "1.3.0", jobCount: 2)).titlebarLabel
            == "Update waits for 2 jobs")
        for status in Self.everyStatus {
            switch status {
            case .available, .waitingForJobs:
                continue
            default:
                #expect(UpdateStatusCopy(status: status).titlebarLabel == nil, "\(status)")
            }
        }
    }

    /// A failure that still knows a newer version keeps the update visible.
    @Test func failureWithKnownVersionKeepsUpdateVisible() {
        let copy = UpdateStatusCopy(status: .failed(
            message: "offline", checkedAt: Self.date, knownVersion: "1.3.0"))
        #expect(copy.titlebarLabel == "Update Available")
        #expect(copy.showsMenuBarItem)
        #expect(copy.canCheck)
        #expect(copy.aboutLine == "The last update check failed.")
    }

    @Test func menuBarItemOnlyWhenAvailable() {
        for status in Self.everyStatus {
            let expected: Bool
            switch status {
            case .available, .waitingForJobs: expected = true
            default: expected = false
            }
            #expect(UpdateStatusCopy(status: status).showsMenuBarItem == expected, "\(status)")
        }
        #expect(UpdateStatusCopy.menuBarItemLabel == "Update available…")
    }

    @Test func checkButtonDisabledWhileCheckingOrUnavailable() {
        for status in Self.everyStatus {
            let expected: Bool
            switch status {
            case .checking, .installing, .unavailable: expected = false
            default: expected = true
            }
            #expect(UpdateStatusCopy(status: status).canCheck == expected, "\(status)")
        }
    }
}
