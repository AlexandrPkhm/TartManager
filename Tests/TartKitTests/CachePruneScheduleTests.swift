import Foundation
import Testing
@testable import TartKit

@Suite struct CachePruneScheduleTests {
    @Test func manualIsNeverAutomaticallyDue() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!CachePruneSchedule.isDue(policy: .manual, lastAttempt: nil, now: now))
        #expect(!CachePruneSchedule.isDue(policy: .manual,
                                         lastAttempt: now.addingTimeInterval(-100_000), now: now))
    }

    @Test func automaticPoliciesAreDueOnlyAtDailyBoundary() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        for policy in [CachePrunePolicy.sevenDays, .fourteenDays, .thirtyDays] {
            #expect(CachePruneSchedule.isDue(policy: policy, lastAttempt: nil, now: now))
            #expect(!CachePruneSchedule.isDue(policy: policy,
                                             lastAttempt: now.addingTimeInterval(-86_399), now: now))
            #expect(CachePruneSchedule.isDue(policy: policy,
                                            lastAttempt: now.addingTimeInterval(-86_400), now: now))
            #expect(!CachePruneSchedule.isDue(policy: policy,
                                             lastAttempt: now.addingTimeInterval(3_600), now: now))
        }
    }
}
