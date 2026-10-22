import Testing
@testable import TartKit

@Suite struct TartVersionSkewPolicyTests {
    private static let v2321 = TartVersion(major: 2, minor: 32, patch: 1)
    private static let v2411 = TartVersion(major: 2, minor: 41, patch: 1)

    private func bundled(_ version: TartVersion) -> TartPrerequisiteStatus {
        .ok(version: version, binaryPath: "/b", source: .bundled)
    }

    private func installed(_ version: TartVersion) -> TartPrerequisiteStatus {
        .ok(version: version, binaryPath: "/i", source: .installed)
    }

    private func report(bundled: TartPrerequisiteStatus?, installed: TartPrerequisiteStatus,
                        selected: TartSource, stored: TartSource?? = nil) -> TartRuntimeReport {
        TartRuntimeReport(bundled: bundled, installed: installed, selected: selected,
                          storedPreference: stored ?? selected)
    }

    @Test func selectedOlderWarns() {
        let report = report(bundled: bundled(Self.v2411), installed: installed(Self.v2321),
                            selected: .installed)
        #expect(TartVersionSkewPolicy.evaluate(report)
            == .selectedIsOlder(selected: Self.v2321, other: Self.v2411))
    }

    @Test func equalVersionsDoNotWarn() {
        let report = report(bundled: bundled(Self.v2411), installed: installed(Self.v2411),
                            selected: .bundled)
        #expect(TartVersionSkewPolicy.evaluate(report) == .none)
    }

    @Test func selectedNewerDoesNotWarn() {
        let report = report(bundled: bundled(Self.v2411), installed: installed(Self.v2321),
                            selected: .bundled)
        #expect(TartVersionSkewPolicy.evaluate(report) == .none)
    }

    @Test func otherNotOkDoesNotWarn() {
        let missing = report(bundled: bundled(Self.v2411), installed: .missing(source: .installed),
                             selected: .bundled)
        #expect(TartVersionSkewPolicy.evaluate(missing) == .none)
        let absent = report(bundled: nil, installed: installed(Self.v2321), selected: .installed)
        #expect(TartVersionSkewPolicy.evaluate(absent) == .none)
    }

    @Test func selectedNotOkDoesNotWarn() {
        let report = report(bundled: .damaged(source: .bundled, reason: "x"),
                            installed: installed(Self.v2411), selected: .bundled)
        #expect(TartVersionSkewPolicy.evaluate(report) == .none)
    }

    @Test func askStateComparesBothSources() {
        let report = report(bundled: bundled(Self.v2411), installed: installed(Self.v2321),
                            selected: .installed, stored: .some(nil))
        #expect(report.storedPreference == nil)
        #expect(TartVersionSkewPolicy.evaluate(report)
            == .selectedIsOlder(selected: Self.v2321, other: Self.v2411))
    }
}
