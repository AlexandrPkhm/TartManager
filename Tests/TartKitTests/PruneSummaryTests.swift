import Testing
import Foundation
@testable import TartKit

@Suite struct PruneSummaryTests {
    @Test func composesReclaimedSpace() {
        let gb: Int64 = 1_073_741_824
        #expect(PruneSummary.compose(freeBefore: 100 * gb, freeAfter: 110 * gb)
                == "Prune complete — freed 10.0 GB")
        #expect(PruneSummary.compose(freeBefore: 10 * gb, freeAfter: 10 * gb)
                == "Nothing to prune.")
        #expect(PruneSummary.compose(freeBefore: 10 * gb, freeAfter: 9 * gb)
                == "Nothing to prune.")
        #expect(PruneSummary.compose(freeBefore: nil, freeAfter: 10 * gb)
                == "Prune complete.")
        #expect(PruneSummary.compose(freeBefore: 10 * gb, freeAfter: nil)
                == "Prune complete.")
    }
}
