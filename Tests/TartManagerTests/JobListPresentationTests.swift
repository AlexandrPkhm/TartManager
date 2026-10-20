import Testing
import Foundation
@testable import TartKit
@testable import TartManager

@Suite struct JobListPresentationTests {
    private func job(_ name: String, _ phase: JobInfo.Phase = .running) -> JobInfo {
        JobInfo(kind: .exportSnapshot(vm: name), phase: phase)
    }

    private func names(_ presentation: JobListPresentation) -> [String] {
        presentation.visibleJobs.map(\.kind.target)
    }

    @Test func noJobsShowsNothing() {
        let presentation = JobListPresentation(jobs: [], isExpanded: false)
        #expect(presentation.isEmpty)
        #expect(presentation.toggleLabel == nil)
    }

    @Test func finishedJobsAreLeftOutAtOnce() {
        let jobs = [job("a", .completed), job("b", .cancelled), job("c", .failed), job("d")]
        let presentation = JobListPresentation(jobs: jobs, isExpanded: false)
        #expect(names(presentation) == ["c", "d"])
        #expect(presentation.toggleLabel == nil)
    }

    @Test func onlyFinishedJobsShowNothing() {
        let presentation = JobListPresentation(jobs: [job("a", .completed)], isExpanded: false)
        #expect(presentation.isEmpty)
    }

    @Test func twoJobsFitWithoutAToggle() {
        let presentation = JobListPresentation(jobs: [job("a"), job("b")], isExpanded: false)
        #expect(names(presentation) == ["a", "b"])
        #expect(presentation.toggleLabel == nil)
        #expect(presentation.toggleSymbol == nil)
    }

    @Test func moreThanTwoJobsCollapseBehindAChevron() {
        let jobs = [job("a"), job("b"), job("c"), job("d")]
        let presentation = JobListPresentation(jobs: jobs, isExpanded: false)
        #expect(names(presentation) == ["a", "b"])
        #expect(presentation.toggleLabel == "Show 2 more jobs")
        #expect(presentation.toggleSymbol == "chevron.down")
    }

    @Test func expandedListShowsAllJobsAndFlipsTheChevron() {
        let jobs = [job("a"), job("b"), job("c")]
        let presentation = JobListPresentation(jobs: jobs, isExpanded: true)
        #expect(names(presentation) == ["a", "b", "c"])
        #expect(presentation.toggleLabel == "Show fewer jobs")
        #expect(presentation.toggleSymbol == "chevron.up")
    }

    @Test func oneHiddenJobUsesTheSingular() {
        let presentation = JobListPresentation(jobs: [job("a"), job("b"), job("c")], isExpanded: false)
        #expect(presentation.toggleLabel == "Show 1 more job")
    }

    @Test func expandedStateHasNoToggleWhenJobsFit() {
        let presentation = JobListPresentation(jobs: [job("a")], isExpanded: true)
        #expect(names(presentation) == ["a"])
        #expect(presentation.toggleLabel == nil)
    }
}
