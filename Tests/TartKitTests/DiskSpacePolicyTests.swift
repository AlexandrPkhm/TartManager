import Testing
import Foundation
@testable import TartKit

@Suite struct DiskSpacePolicyTests {
    @Test func ampleSpaceIsOk() {
        let verdict = DiskSpacePolicy.verdict(
            freeBytes: 100 * 1_000_000_000, estimatedNeedBytes: 10 * 1_000_000_000)
        #expect(verdict == .ok(freeBytes: 100 * 1_000_000_000))
        #expect(verdict?.isTight == false)
    }

    @Test func estimateAt95PercentIsTight() {
        let verdict = DiskSpacePolicy.verdict(
            freeBytes: 100, estimatedNeedBytes: 95)
        #expect(verdict == .tight(freeBytes: 100, estimatedNeedBytes: 95))
        #expect(verdict?.isTight == true)
    }

    @Test func estimateBeyondFreeIsTight() {
        let verdict = DiskSpacePolicy.verdict(
            freeBytes: 50, estimatedNeedBytes: 100)
        #expect(verdict == .tight(freeBytes: 50, estimatedNeedBytes: 100))
    }

    @Test func unknownInputsYieldNoGate() {
        #expect(DiskSpacePolicy.verdict(freeBytes: 0, estimatedNeedBytes: 10) == nil)
        #expect(DiskSpacePolicy.verdict(freeBytes: 10, estimatedNeedBytes: 0) == nil)
        #expect(DiskSpacePolicy.verdict(freeBytes: 10, estimatedNeedBytes: 10)?.isTight == true)
    }

    @Test func liveProbeReturnsPositiveForTempDirectory() {
        let free = DiskSpace.freeBytes(atPath: FileManager.default.temporaryDirectory.path)
        #expect(free != nil)
        #expect(free! > 0)
    }

    @Test func remoteImageEstimateIsDocumentedConstant() {
        #expect(DiskSpacePolicy.remoteImageEstimateBytes == 80 * 1_073_741_824)
    }

    @Test func importEstimateAppliesDocumentedMultiplier() {
        #expect(DiskSpacePolicy.archiveExpansionMultiplier == 2.5)
        #expect(DiskSpacePolicy.importEstimate(archiveFileSizeBytes: 10 * 1_073_741_824)
                    == 25 * 1_073_741_824)
    }

    @Test func fileSizeProbeReadsRealFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("archive.tvm").path
        try "0123456789".write(toFile: file, atomically: true, encoding: .utf8)
        #expect(DiskSpace.fileSizeBytes(atPath: file) == 10)
        #expect(DiskSpace.fileSizeBytes(atPath: "/nonexistent/archive.tvm") == nil)
    }

    /// Finding 7: the import pre-flight verdict is a tested policy-layer
    /// function (estimate × threshold), not view code.
    @Test func importVerdictComposesEstimateAndThreshold() {
        let gb: Int64 = 1_073_741_824
        #expect(DiskSpacePolicy.importVerdict(archiveFileSizeBytes: 10 * gb, freeBytes: 100 * gb)
                    == .ok(freeBytes: 100 * gb))
        #expect(DiskSpacePolicy.importVerdict(archiveFileSizeBytes: 40 * gb, freeBytes: 100 * gb)
                    == .tight(freeBytes: 100 * gb, estimatedNeedBytes: 100 * gb))
        #expect(DiskSpacePolicy.importVerdict(archiveFileSizeBytes: 0, freeBytes: 100 * gb) == nil)
    }

    @Test func exportVerdictUsesVMOnDiskSizeAsEstimate() {
        let gb: Int64 = 1_073_741_824
        #expect(DiskSpacePolicy.exportEstimate(vmDiskUsageGB: 20) == 20 * gb)
        #expect(DiskSpacePolicy.exportVerdict(vmDiskUsageGB: 20, freeBytes: 100 * gb)
                == .ok(freeBytes: 100 * gb))
        #expect(DiskSpacePolicy.exportVerdict(vmDiskUsageGB: 95, freeBytes: 100 * gb)
                == .tight(freeBytes: 100 * gb, estimatedNeedBytes: 95 * gb))
        #expect(DiskSpacePolicy.exportVerdict(vmDiskUsageGB: 0, freeBytes: 100 * gb) == nil)
    }

    /// finding 3: the pre-check probes the DESTINATION's volume even when the
    /// snapshots folder does not exist yet — the probe walks up to the
    /// nearest existing directory.
    @Test func destinationProbeFallsBackToNearestExistingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        let direct = DiskSpace.freeBytes(atPath: dir.path)
        #expect(direct != nil)
        let missing = dir.appendingPathComponent("snapshots/not-yet").path
        let destination = DiskSpace.freeBytes(forDestination: missing)
        #expect(destination != nil)
        // The two probes are separate resource queries; free space on a live
        // volume drifts slightly between them. Same-volume agreement is the
        // contract — 1% tolerance absorbs the drift, never a different volume.
        let tolerance = direct! / 100
        #expect(abs(destination! - direct!) <= tolerance)
    }

    // --- IPSW estimates and disk-size rules ---

    @Test func ipswEstimateConstantsAreDocumented() {
        #expect(DiskSpacePolicy.ipswRestoreExpansionMultiplier == 2.0)
        #expect(DiskSpacePolicy.latestIPSWEstimateBytes == 20 * 1_073_741_824)
    }

    @Test func localIPSWEstimateAppliesExpansionPlusDiskSize() {
        let estimate = DiskSpacePolicy.ipswEstimateBytes(
            usesLatest: false, ipswFileSizeBytes: 12 * 1_073_741_824, diskSizeGB: 50)
        #expect(estimate == Int64(24 * 1_073_741_824 + 50 * 1_073_741_824))
    }

    @Test func latestIPSWEstimateUsesConstantPlusDiskSize() {
        let estimate = DiskSpacePolicy.ipswEstimateBytes(
            usesLatest: true, ipswFileSizeBytes: nil, diskSizeGB: 50)
        #expect(estimate == Int64(20 * 1_073_741_824 + 50 * 1_073_741_824))
    }

    @Test func localModeWithoutAReadableFileYieldsNoEstimate() {
        // The local probe is used only in local mode; a missing file is
        // "unknown", never a stale size.
        #expect(DiskSpacePolicy.ipswEstimateBytes(
            usesLatest: false, ipswFileSizeBytes: nil, diskSizeGB: 50) == nil)
        #expect(DiskSpacePolicy.ipswVerdict(
            usesLatest: false, ipswFileSizeBytes: nil, diskSizeGB: 50,
            freeBytes: 100 * 1_073_741_824) == nil)
    }

    @Test func ipswVerdictComposesEstimateAndThreshold() {
        let gb: Int64 = 1_073_741_824
        #expect(DiskSpacePolicy.ipswVerdict(
            usesLatest: true, ipswFileSizeBytes: nil, diskSizeGB: 50,
            freeBytes: 100 * gb) == .ok(freeBytes: 100 * gb))
        #expect(DiskSpacePolicy.ipswVerdict(
            usesLatest: true, ipswFileSizeBytes: nil, diskSizeGB: 50,
            freeBytes: 70 * gb) == .tight(freeBytes: 70 * gb, estimatedNeedBytes: 70 * gb))
        #expect(DiskSpacePolicy.ipswVerdict(
            usesLatest: true, ipswFileSizeBytes: nil, diskSizeGB: 50,
            freeBytes: nil) == nil)
    }

    @Test func diskSizeParsingAcceptsWholePositiveBoundedValues() {
        #expect(IPSWCreateRules.parseDiskSizeGB("50") == 50)
        #expect(IPSWCreateRules.parseDiskSizeGB(" 64 ") == 64)
        #expect(IPSWCreateRules.parseDiskSizeGB("1") == 1)
        #expect(IPSWCreateRules.parseDiskSizeGB("4096") == 4096)
        #expect(IPSWCreateRules.isValidDiskSizeText("50"))
    }

    @Test func diskSizeParsingRejectsInvalidValuesInsteadOfFallingBack() {
        // Empty, negative, zero, fractional, non-numeric, and oversized
        // inputs are all invalid — there is no `?? 50` fallback anywhere.
        #expect(IPSWCreateRules.parseDiskSizeGB("") == nil)
        #expect(IPSWCreateRules.parseDiskSizeGB("-5") == nil)
        #expect(IPSWCreateRules.parseDiskSizeGB("0") == nil)
        #expect(IPSWCreateRules.parseDiskSizeGB("12.5") == nil)
        #expect(IPSWCreateRules.parseDiskSizeGB("abc") == nil)
        #expect(IPSWCreateRules.parseDiskSizeGB("4097") == nil)
        // A value beyond Int64 range is non-numeric text — no trap.
        #expect(IPSWCreateRules.parseDiskSizeGB("9223372036854775808") == nil)
    }

    @Test func diskSizeCeilingKeepsByteConversionOverflowProof() {
        // 4096 GB × 2^30 = 2^42, far inside Int64 — the ceiling is what makes
        // the estimate arithmetic overflow-proof by construction.
        #expect(Int64(IPSWCreateRules.maxDiskSizeGB) * 1_073_741_824 == 4_398_046_511_104)
    }
}
