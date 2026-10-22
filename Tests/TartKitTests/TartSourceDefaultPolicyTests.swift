import Testing
@testable import TartKit

@Suite struct TartSourceDefaultPolicyTests {
    private static let bundledOk = TartPrerequisiteStatus.ok(
        version: TartVersion(major: 2, minor: 41, patch: 1), binaryPath: "/b", source: .bundled)
    private static let installedOk = TartPrerequisiteStatus.ok(
        version: TartVersion(major: 2, minor: 32, patch: 1), binaryPath: "/i", source: .installed)
    private static let bundledDamaged = TartPrerequisiteStatus.damaged(source: .bundled, reason: "x")
    private static let installedMissing = TartPrerequisiteStatus.missing(source: .installed)

    private func report(bundled: TartPrerequisiteStatus?, installed: TartPrerequisiteStatus,
                        stored: TartSource? = nil) -> TartRuntimeReport {
        TartRuntimeReport(bundled: bundled, installed: installed,
                          selected: stored ?? .installed, storedPreference: stored)
    }

    @Test func storedPreferenceNeverDecides() {
        for stored in [TartSource.bundled, .installed] {
            #expect(TartSourceDefaultPolicy.decide(
                report(bundled: Self.bundledOk, installed: Self.installedOk, stored: stored)) == .keep)
        }
    }

    @Test func noBundledStoresInstalled() {
        #expect(TartSourceDefaultPolicy.decide(
            report(bundled: nil, installed: Self.installedOk)) == .store(.installed))
        #expect(TartSourceDefaultPolicy.decide(
            report(bundled: nil, installed: Self.installedMissing)) == .store(.installed))
    }

    @Test func bothOkAsks() {
        #expect(TartSourceDefaultPolicy.decide(
            report(bundled: Self.bundledOk, installed: Self.installedOk)) == .ask)
    }

    @Test func bundledOkInstalledFailedStoresBundled() {
        #expect(TartSourceDefaultPolicy.decide(
            report(bundled: Self.bundledOk, installed: Self.installedMissing)) == .store(.bundled))
    }

    @Test func bundledFailedInstalledOkStoresInstalled() {
        #expect(TartSourceDefaultPolicy.decide(
            report(bundled: Self.bundledDamaged, installed: Self.installedOk)) == .store(.installed))
    }

    @Test func bothFailedStoresBundled() {
        #expect(TartSourceDefaultPolicy.decide(
            report(bundled: Self.bundledDamaged, installed: Self.installedMissing)) == .store(.bundled))
    }
}
