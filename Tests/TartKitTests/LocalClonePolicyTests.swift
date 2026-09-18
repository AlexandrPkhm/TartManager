import Testing
@testable import TartKit

@Suite struct LocalClonePolicyTests {
    func entry(diskUsage: Double) -> VMEntry {
        VMEntry(name: "golden-vm", source: "local", running: false,
                state: "stopped", diskSize: diskUsage, diskUsage: diskUsage, accessed: nil)
    }

    @Test func estimateConvertsTartGBIntoBytes() {
        // Research: tart 2.32's list reports `Size`/`Disk` in GB (the real
        // ~50 GB VM on this host reports 50). One GiB per unit.
        #expect(DiskSpacePolicy.localCloneEstimateBytes(for: entry(diskUsage: 25))
                == 25 * 1_073_741_824)
    }

    @Test func zeroOrUnknownInputsYieldNoGate() {
        // Never block on unknown inputs: estimate 0 (tart reported no size)
        // or unknown free space means no verdict, no dialog.
        #expect(DiskSpacePolicy.localCloneVerdict(freeBytes: 100_000, source: entry(diskUsage: 0)) == nil)
        #expect(DiskSpacePolicy.localCloneVerdict(freeBytes: nil, source: entry(diskUsage: 25)) == nil)
    }

    @Test func ampleFreeSpaceIsOk() {
        #expect(DiskSpacePolicy.localCloneVerdict(freeBytes: 1_000 * 1_073_741_824,
                                                  source: entry(diskUsage: 25))
                == .ok(freeBytes: 1_000 * 1_073_741_824))
    }

    @Test func estimateNearFreeSpaceIsTight() {
        // 25 GiB need against 26 GiB free is 96% — at/above the 95% threshold.
        #expect(DiskSpacePolicy.localCloneVerdict(freeBytes: 26 * 1_073_741_824,
                                                  source: entry(diskUsage: 25))?.isTight == true)
    }
}
