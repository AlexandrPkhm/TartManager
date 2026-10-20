import Testing
@testable import TartKit

@Suite struct UpdateInstallGateTests {
    private func job(_ phase: JobInfo.Phase) -> JobInfo {
        JobInfo(kind: .prune, phase: phase)
    }

    @Test func noJobsInstallsNow() {
        #expect(UpdateInstallGate.decide(activeJobs: []) == .installNow)
    }

    @Test func runningJobsPostpone() {
        #expect(UpdateInstallGate.decide(activeJobs: [job(.running), job(.running)]) == .postpone(jobCount: 2))
    }

    @Test func terminalJobsDoNotBlock() {
        let jobs = [job(.completed), job(.failed), job(.cancelled)]
        #expect(UpdateInstallGate.decide(activeJobs: jobs) == .installNow)
    }

    @Test func mixedJobsCountOnlyRunning() {
        let jobs = [job(.running), job(.completed), job(.failed)]
        #expect(UpdateInstallGate.decide(activeJobs: jobs) == .postpone(jobCount: 1))
    }
}
