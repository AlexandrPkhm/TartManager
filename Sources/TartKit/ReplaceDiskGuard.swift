import Foundation

/// The pre-spawn refusal decision for Replace Disk, as a pure tested function
/// (the issue's automated checks: typed-name gate first, stopped-only, local
/// only). The gate reuses Issue 15's tested `RestoreGate` so the destructive
/// confirmations share one rule (findings 2, 6).
public enum ReplaceDiskGuard {
    public enum Refusal: Equatable, Sendable {
        /// The typed name does not match exactly (or no source image was
        /// chosen). Equivalent to a cancel at the gate: nothing may run.
        case gateFailed
        /// Only local VMs have replaceable disks.
        case notLocal
        case running
        case suspended
        /// An existing job already targets the VM (produced by
        /// `ReplaceDiskCoordinator`, not by this pure function).
        case inFlight
    }

    public static func refusal(vm: VMEntry, typedName: String, path: String) -> Refusal? {
        if path.isEmpty || !RestoreGate.allowsProceed(typedName: typedName, vmName: vm.name) {
            return .gateFailed
        }
        if !vm.isLocal { return .notLocal }
        if vm.running { return .running }
        if vm.isSuspended { return .suspended }
        return nil
    }
}
