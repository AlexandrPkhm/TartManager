import Testing
import Foundation
@testable import TartKit
@testable import TartManager

@Suite struct JobRowCopyTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func job(_ kind: JobInfo.Kind = .exportSnapshot(vm: "macos14-sonoma"),
                     phase: JobInfo.Phase = .running,
                     progress: PullProgress? = nil,
                     error: TartOperationError? = nil,
                     summary: String? = nil) -> JobInfo {
        JobInfo(kind: kind, createdAt: start, phase: phase,
                progress: progress, error: error, summary: summary)
    }

    @Test func runningJobWithFractionShowsPercentAndElapsed() {
        let copy = JobRowCopy(job: job(progress: PullProgress(fraction: 0.42, note: nil)),
                              now: start.addingTimeInterval(72))
        #expect(copy.title == "Snapshotting “macos14-sonoma”")
        #expect(copy.caption == "42% · 1:12")
    }

    @Test func runningJobWithoutFractionShowsNoPercent() {
        let copy = JobRowCopy(job: job(), now: start.addingTimeInterval(5))
        #expect(copy.caption == "0:05")
    }

    @Test func runningJobShowsProgressNote() {
        let progress = PullProgress(fraction: nil, note: "Waiting for cache cleanup…")
        let copy = JobRowCopy(job: job(progress: progress), now: start.addingTimeInterval(3))
        #expect(copy.caption == "Waiting for cache cleanup… · 0:03")
    }

    @Test func emptyProgressNoteIsSkipped() {
        let progress = PullProgress(fraction: 0.5, note: "")
        let copy = JobRowCopy(job: job(progress: progress), now: start)
        #expect(copy.caption == "50% · 0:00")
    }

    @Test func failedJobShowsTheErrorMessage() {
        let error = TartOperationError(operation: "export", message: "disk full", rawDetails: "")
        let copy = JobRowCopy(job: job(phase: .failed, error: error), now: start)
        #expect(copy.caption == "disk full")
    }

    @Test func failedJobWithoutErrorShowsGenericCaption() {
        #expect(JobRowCopy(job: job(phase: .failed), now: start).caption == "Failed")
    }

    @Test func finishedJobsShowTheirOutcome() {
        #expect(JobRowCopy(job: job(phase: .completed), now: start).caption == "Done")
        #expect(JobRowCopy(job: job(phase: .completed, summary: "Freed 2 GB"), now: start).caption
                == "Freed 2 GB")
        #expect(JobRowCopy(job: job(phase: .cancelled), now: start).caption == "Cancelled")
    }

    @Test func elapsedUsesMinutesThenHours() {
        #expect(JobRowCopy.elapsed(from: start, to: start.addingTimeInterval(59)) == "0:59")
        #expect(JobRowCopy.elapsed(from: start, to: start.addingTimeInterval(600)) == "10:00")
        #expect(JobRowCopy.elapsed(from: start, to: start.addingTimeInterval(3_725)) == "1:02:05")
        #expect(JobRowCopy.elapsed(from: start, to: start.addingTimeInterval(-10)) == "0:00")
    }

    @Test func titlesNameEveryKind() {
        #expect(JobRowCopy.title(for: .clone(name: "a", source: "ghcr.io/cirruslabs/macos:latest"))
                == "Creating “a” from macos:latest")
        #expect(JobRowCopy.title(for: .clone(name: "a", source: "b")) == "Creating “a” from b")
        #expect(JobRowCopy.title(for: .importArchive(name: "a", path: "/tmp/x/vm.tvm"))
                == "Importing “a” from vm.tvm")
        #expect(JobRowCopy.title(for: .restoreSnapshot(vm: "a")) == "Restoring “a” from a snapshot")
        #expect(JobRowCopy.title(for: .createFromIPSW(name: "a")) == "Installing “a” from an IPSW")
        #expect(JobRowCopy.title(for: .deleteVM(name: "a")) == "Deleting “a”")
        #expect(JobRowCopy.title(for: .replaceDisk(name: "a", path: "/d.img"))
                == "Replacing the disk of “a”")
        #expect(JobRowCopy.title(for: .prune) == "Pruning caches")
    }
}
