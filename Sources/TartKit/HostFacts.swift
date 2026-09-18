import Foundation

/// Real system facts the resource warnings are computed against.
public struct HostFacts: Equatable, Sendable {
    public let memoryBytes: Int
    public let coreCount: Int

    public init(memoryBytes: Int, coreCount: Int) {
        self.memoryBytes = memoryBytes
        self.coreCount = coreCount
    }

    /// Physical RAM in MB — the single bytes→MB conversion point for host
    /// memory (the run-time over-commitment policy and the resource
    /// validator both consume it).
    public var hostMemoryMB: Int { memoryBytes / 1_048_576 }

    public static func current() -> HostFacts {
        HostFacts(memoryBytes: Int(ProcessInfo.processInfo.physicalMemory),
                  coreCount: ProcessInfo.processInfo.processorCount)
    }
}
