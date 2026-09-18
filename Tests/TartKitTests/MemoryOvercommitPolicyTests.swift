import Testing
@testable import TartKit

@Suite struct MemoryOvercommitPolicyTests {
    let host = HostFacts(memoryBytes: 16 * 1024 * 1_048_576, coreCount: 8)

    @Test func hostFactsExposeMemoryInMB() {
        // One host-side conversion point, one value.
        #expect(host.hostMemoryMB == 16384)
    }

    @Test func sumsRunningAndTargetMemory() {
        let assessment = MemoryOvercommitPolicy.assess(
            runningMemoryMB: 6144, targetMemoryMB: 8192, host: host)
        #expect(assessment.runningMemoryMB == 6144)
        #expect(assessment.targetMemoryMB == 8192)
        #expect(assessment.totalMemoryMB == 14336)
        #expect(assessment.hostMemoryMB == 16384)
    }

    @Test func doesNotWarnBelowThreshold() {
        let assessment = MemoryOvercommitPolicy.assess(
            runningMemoryMB: 2048, targetMemoryMB: 4096, host: host)
        #expect(!assessment.shouldWarn)
    }

    @Test func warnsExactlyAtTheNinetyPercentBoundary() {
        // 0.9 × 16384 = 14745.6 — the boundary sits between 14745 and 14746.
        #expect(!MemoryOvercommitPolicy.assess(
            runningMemoryMB: 8192, targetMemoryMB: 6553, host: host).shouldWarn)
        #expect(MemoryOvercommitPolicy.assess(
            runningMemoryMB: 8192, targetMemoryMB: 6554, host: host).shouldWarn)
    }

    @Test func warnsWellBeyondHostRAM() {
        let assessment = MemoryOvercommitPolicy.assess(
            runningMemoryMB: 8192, targetMemoryMB: 32768, host: host)
        #expect(assessment.shouldWarn)
    }

    @Test func summaryTextContainsTheArithmetic() {
        let assessment = MemoryOvercommitPolicy.assess(
            runningMemoryMB: 8192, targetMemoryMB: 8192, host: host)
        #expect(assessment.summaryText.contains("8192 MB"))
        #expect(assessment.summaryText.contains("16384 MB"))
    }

    @Test func decideReturnsProceedBelowThreshold() {
        // The proceed path is explicitly ungated: below the shared fraction
        // the decision is .proceed and the AppModel wiring runs the VM with
        // no dialog and no gate.
        let decision = MemoryOvercommitPolicy.decide(
            runningMemoryMB: 4096, targetMemoryMB: 4096, host: host)
        #expect(decision == .proceed)
    }

    @Test func decideReturnsWarnWithAssessmentAtThreshold() {
        guard case .warn(let assessment) = MemoryOvercommitPolicy.decide(
            runningMemoryMB: 8192, targetMemoryMB: 8192, host: host) else {
            Issue.record("expected .warn")
            return
        }
        #expect(assessment.totalMemoryMB == 16384)
        #expect(assessment.shouldWarn)
    }
}
