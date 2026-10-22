import Testing
@testable import TartKit

@Suite struct TartSourceSwitchGateTests {
    private func job(_ phase: JobInfo.Phase) -> JobInfo {
        JobInfo(kind: .prune, phase: phase)
    }

    @Test func noJobsAllow() {
        #expect(TartSourceSwitchGate.decide(activeJobs: []) == .allow)
    }

    @Test func runningJobRefuses() {
        #expect(TartSourceSwitchGate.decide(activeJobs: [job(.running)]) == .refuse(jobCount: 1))
    }

    @Test func terminalJobsAllow() {
        let jobs = [job(.completed), job(.failed), job(.cancelled)]
        #expect(TartSourceSwitchGate.decide(activeJobs: jobs) == .allow)
    }

    @Test func refusalMessageCountsJobs() {
        #expect(TartSourceSwitchGate.refusalMessage(jobCount: 1)
            == "Finish or cancel 1 running job to change the tart source.")
        #expect(TartSourceSwitchGate.refusalMessage(jobCount: 2)
            == "Finish or cancel 2 running jobs to change the tart source.")
    }

    @Test func mixedCountsOnlyRunning() {
        let jobs = [job(.running), job(.completed), job(.failed)]
        #expect(TartSourceSwitchGate.decide(activeJobs: jobs) == .refuse(jobCount: 1))
    }
}
