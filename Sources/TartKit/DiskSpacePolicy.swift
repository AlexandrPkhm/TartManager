import Foundation

/// Pre-flight disk-space gate for space-hungry operations.
public enum DiskSpacePolicy {
    /// Conservative estimate for cloning an unknown-size remote macOS image
    /// (a base image unpacks to ~65–70 GB). Documented heuristic, tuneable.
    public static let remoteImageEstimateBytes: Int64 = 80 * 1_073_741_824

    public enum Verdict: Equatable, Sendable {
        case ok(freeBytes: Int64)
        case tight(freeBytes: Int64, estimatedNeedBytes: Int64)

        /// True only for `.tight` — views ask the verdict directly instead
        /// of an Optional extension (finding 15).
        public var isTight: Bool {
            if case .tight = self { return true }
            return false
        }
    }

    /// nil (no gate) when inputs are unknown; otherwise ok/tight at the 95% threshold.
    public static func verdict(freeBytes: Int64, estimatedNeedBytes: Int64) -> Verdict? {
        guard freeBytes > 0, estimatedNeedBytes > 0 else { return nil }
        if estimatedNeedBytes >= (freeBytes * 95 / 100) {
            return .tight(freeBytes: freeBytes, estimatedNeedBytes: estimatedNeedBytes)
        }
        return .ok(freeBytes: freeBytes)
    }

    /// Estimated bytes a local clone may need: worst case is a full copy of
    /// the source's on-disk usage. `VMEntry.diskUsage` is tart 2.32's `Size`
    /// key in GB (verified against the real CLI on this host — a ~50 GB VM
    /// reports `"Size": 50`), matching the list row's display convention.
    /// This helper is the single place the unit assumption lives (finding 3).
    public static func localCloneEstimateBytes(for source: VMEntry) -> Int64 {
        guard source.diskUsage > 0 else { return 0 }
        return Int64((source.diskUsage * 1_073_741_824).rounded(.up))
    }

    /// Centralized clone pre-check verdict (finding 3): probe + estimate +
    /// threshold, consumed by the dialog through AppModel. nil = no gate
    /// (unknown free space or unknown estimate — never block on unknowns).
    public static func localCloneVerdict(freeBytes: Int64?,
                                         source: VMEntry) -> Verdict? {
        guard let freeBytes, freeBytes > 0 else { return nil }
        return verdict(freeBytes: freeBytes,
                       estimatedNeedBytes: localCloneEstimateBytes(for: source))
    }
}

public enum DiskSpace {
    /// Volume free capacity for a path, or nil when unresolvable.
    public static func freeBytes(atPath path: String) -> Int64? {
        do {
            let values = try URL(fileURLWithPath: path)
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            return values.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
        } catch {
            return nil
        }
    }

    /// File size in bytes for an existing file, or nil.
    public static func fileSizeBytes(atPath path: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else { return nil }
        return size.int64Value
    }
}

extension DiskSpacePolicy {
    /// Conservative expansion factor for .tvm archives (compressed disk images;
    /// macOS base images: ~27 GB compressed → ~65–70 GB raw).
    public static let archiveExpansionMultiplier: Double = 2.5

    public static func importEstimate(archiveFileSizeBytes: Int64) -> Int64 {
        Int64(Double(archiveFileSizeBytes) * archiveExpansionMultiplier)
    }

    /// The import pre-flight gate: archive estimate against free space at the
    /// standard 95%-of-free tight threshold. The single source of truth for
    /// the import space verdict — views render it, they never compute it.
    public static func importVerdict(archiveFileSizeBytes: Int64, freeBytes: Int64) -> Verdict? {
        guard archiveFileSizeBytes > 0 else { return nil }
        return verdict(freeBytes: freeBytes,
                       estimatedNeedBytes: importEstimate(archiveFileSizeBytes: archiveFileSizeBytes))
    }
}

extension DiskSpacePolicy {
    /// Bytes per GB for tart's `Size` (disk usage) key. tart 2.32 reports GB
    /// for local VMs; the model field is unit-neutral (Issue 3), so the
    /// conversion lives here — a single point if units ever differ.
    public static let gibibyte: Int64 = 1_073_741_824

    /// The snapshot-export estimate is the VM's on-disk size (the compressed
    /// archive is smaller — a safe, conservative upper bound).
    public static func exportEstimate(vmDiskUsageGB: Double) -> Int64 {
        Int64(vmDiskUsageGB * Double(gibibyte))
    }

    /// The snapshot-export pre-flight gate at the standard 95%-of-free tight
    /// threshold. The view renders this verdict; it never computes it.
    public static func exportVerdict(vmDiskUsageGB: Double, freeBytes: Int64) -> Verdict? {
        guard vmDiskUsageGB > 0 else { return nil }
        return verdict(freeBytes: freeBytes,
                       estimatedNeedBytes: exportEstimate(vmDiskUsageGB: vmDiskUsageGB))
    }
}

extension DiskSpace {
    /// Volume free capacity for a DESTINATION path that may not exist yet:
    /// walks up to the nearest existing directory and probes that volume.
    /// The snapshots pre-check must measure the destination's volume — the
    /// snapshots folder is configurable and can live on a different volume
    /// than VM storage (finding 3).
    public static func freeBytes(forDestination path: String) -> Int64? {
        var candidate = path
        var isDirectory: ObjCBool = false
        while !FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory) {
            let parent = (candidate as NSString).deletingLastPathComponent
            if parent == candidate { return nil } // reached the root; nothing to probe
            candidate = parent
        }
        return freeBytes(atPath: candidate)
    }
}

extension DiskSpacePolicy {
    /// Conservative estimate for a "latest supported" macOS IPSW install: the
    /// fetched image size is unknown up front and the current macOS restore
    /// image is ~12–18 GB — 20 GiB covers it with headroom (documented
    /// heuristic, the `remoteImageEstimateBytes` analog).
    public static let latestIPSWEstimateBytes: Int64 = 20 * 1_073_741_824

    /// Documented expansion factor for a local IPSW install: the restore
    /// keeps the compressed IPSW on disk and writes its unpacked install
    /// payload — charging ~2× the file size before adding the VM disk is the
    /// conservative stance import already takes with its 2.5× multiplier.
    public static let ipswRestoreExpansionMultiplier: Double = 2.0

    /// The pre-flight estimate for an IPSW create; nil = unknown ⇒ no gate.
    /// Mode selection is explicit: the local-file probe is only consulted in
    /// local mode, so toggling "latest" can never pick up a stale picked
    /// file's size. The `IPSWCreateRules` 4096 GB ceiling keeps the disk-size
    /// term ≤ 2^42, so the arithmetic cannot overflow.
    public static func ipswEstimateBytes(usesLatest: Bool,
                                         ipswFileSizeBytes: Int64?,
                                         diskSizeGB: Int) -> Int64? {
        let diskBytes = Int64(diskSizeGB) * 1_073_741_824
        if usesLatest {
            return latestIPSWEstimateBytes + diskBytes
        }
        guard let ipswFileSizeBytes else { return nil }
        return Int64(Double(ipswFileSizeBytes) * ipswRestoreExpansionMultiplier) + diskBytes
    }

    /// The IPSW pre-flight verdict at the standard 95%-of-free tight
    /// threshold; nil when inputs are unknown (never a fabricated gate).
    public static func ipswVerdict(usesLatest: Bool,
                                   ipswFileSizeBytes: Int64?,
                                   diskSizeGB: Int,
                                   freeBytes: Int64?) -> Verdict? {
        guard let freeBytes,
              let estimate = ipswEstimateBytes(usesLatest: usesLatest,
                                               ipswFileSizeBytes: ipswFileSizeBytes,
                                               diskSizeGB: diskSizeGB) else { return nil }
        return verdict(freeBytes: freeBytes, estimatedNeedBytes: estimate)
    }
}

/// Disk-size draft validation for the IPSW create: whole-number GB only,
/// strictly positive, and bounded by a documented ceiling that keeps every
/// downstream byte arithmetic overflow-proof. Invalid text is rejected
/// outright — callers never fall back to a default value.
public enum IPSWCreateRules {
    /// Ceiling: 4096 GB × 2^30 = 2^42 « Int64.max.
    public static let maxDiskSizeGB = 4096

    /// Parses "50" → 50; nil for empty, negative, zero, fractional,
    /// non-numeric, and oversized text.
    public static func parseDiskSizeGB(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isNumber }),
              let value = Int(trimmed),
              (1...maxDiskSizeGB).contains(value) else { return nil }
        return value
    }

    public static func isValidDiskSizeText(_ text: String) -> Bool {
        parseDiskSizeGB(text) != nil
    }
}
