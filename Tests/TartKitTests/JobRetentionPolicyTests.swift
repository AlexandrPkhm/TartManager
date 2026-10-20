import Testing
@testable import TartKit

@Suite struct JobRetentionPolicyTests {
    @Test func listShowsRunningAndFailedJobsOnly() {
        #expect(JobRetentionPolicy.isListed(.running))
        #expect(JobRetentionPolicy.isListed(.failed))
        #expect(!JobRetentionPolicy.isListed(.completed))
        #expect(!JobRetentionPolicy.isListed(.cancelled))
    }

    @Test func completedAndCancelledRecordsAreReleased() {
        #expect(JobRetentionPolicy.releasesAutomatically(.completed))
        #expect(JobRetentionPolicy.releasesAutomatically(.cancelled))
        #expect(!JobRetentionPolicy.releasesAutomatically(.running))
        #expect(!JobRetentionPolicy.releasesAutomatically(.failed))
    }

    @Test func releaseDelayIsBounded() {
        #expect(JobRetentionPolicy.releaseDelay > .zero)
        #expect(JobRetentionPolicy.releaseDelay <= .seconds(10))
    }
}
