import Foundation

/// Soft guardrail against host-memory over-commitment when running VMs.
/// Pure math and summary text: the allocation gathering lives in
/// InventoryService and the Run-path wiring in AppModel.
public enum MemoryOvercommitPolicy {
    public struct Assessment: Equatable, Sendable {
        public let runningMemoryMB: Int
        public let targetMemoryMB: Int
        public let hostMemoryMB: Int

        public var totalMemoryMB: Int { runningMemoryMB + targetMemoryMB }

        public var shouldWarn: Bool {
            Double(totalMemoryMB) >= Double(hostMemoryMB) * HostMemoryWarnings.warningFraction
        }

        public var summaryText: String {
            "Running VMs use \(runningMemoryMB) MB; starting this VM adds "
                + "\(targetMemoryMB) MB — \(totalMemoryMB) MB of \(hostMemoryMB) MB host RAM."
        }
    }

    /// The decide-to-warn step of the run flow, extracted so the proceed
    /// branch is unit-testable. Below the shared fraction the run proceeds
    /// ungated; at/above it, the warning (with its arithmetic) is
    /// returned. Non-blocking by construction.
    public enum RunMemoryDecision: Equatable, Sendable {
        case proceed
        case warn(Assessment)
    }

    /// Explicit boundary: the caller sums the running allocations from the
    /// named `MemoryAllocationSnapshot` — no positional array invariants
    /// exist anywhere.
    public static func assess(runningMemoryMB: Int,
                              targetMemoryMB: Int,
                              host: HostFacts) -> Assessment {
        Assessment(runningMemoryMB: runningMemoryMB,
                   targetMemoryMB: targetMemoryMB,
                   hostMemoryMB: host.hostMemoryMB)
    }

    public static func decide(runningMemoryMB: Int,
                              targetMemoryMB: Int,
                              host: HostFacts) -> RunMemoryDecision {
        let assessment = assess(runningMemoryMB: runningMemoryMB,
                                targetMemoryMB: targetMemoryMB,
                                host: host)
        return assessment.shouldWarn ? .warn(assessment) : .proceed
    }
}
