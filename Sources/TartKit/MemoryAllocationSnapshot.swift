/// Named boundary between the allocation gather and the policy: running
/// allocations and the target are separate fields, so no positional
/// invariant can silently reassign which value is the target. Unknown or
/// failed configs contribute 0 per slot.
public struct MemoryAllocationSnapshot: Equatable, Sendable {
    public let runningMB: [Int]
    public let targetMB: Int

    public init(runningMB: [Int], targetMB: Int) {
        self.runningMB = runningMB
        self.targetMB = targetMB
    }
}
