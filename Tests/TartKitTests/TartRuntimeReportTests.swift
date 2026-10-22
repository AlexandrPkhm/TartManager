import Testing
@testable import TartKit

@Suite struct TartRuntimeReportTests {
    private static let bundledOk = TartPrerequisiteStatus.ok(
        version: TartVersion(major: 2, minor: 41, patch: 1), binaryPath: "/b", source: .bundled)
    private static let installedOk = TartPrerequisiteStatus.ok(
        version: TartVersion(major: 2, minor: 32, patch: 1), binaryPath: "/i", source: .installed)

    private func report(bundled: TartPrerequisiteStatus? = bundledOk,
                        installed: TartPrerequisiteStatus = installedOk,
                        selected: TartSource) -> TartRuntimeReport {
        TartRuntimeReport(bundled: bundled, installed: installed,
                          selected: selected, storedPreference: selected)
    }

    @Test func activeFollowsSelection() {
        #expect(report(selected: .bundled).active == Self.bundledOk)
        #expect(report(selected: .installed).active == Self.installedOk)
        #expect(report(bundled: nil, selected: .bundled).active == .missing(source: .bundled))
    }

    @Test func otherIsTheUnselectedSource() {
        #expect(report(selected: .bundled).other == Self.installedOk)
        #expect(report(selected: .installed).other == Self.bundledOk)
        #expect(report(bundled: nil, selected: .installed).other == nil)
    }

    @Test func selectingSwapsWithoutRecheck() {
        let original = report(selected: .installed)
        let swapped = original.selecting(.bundled)
        #expect(swapped.selected == .bundled)
        #expect(swapped.bundled == original.bundled)
        #expect(swapped.installed == original.installed)
        #expect(swapped.active == Self.bundledOk)
    }

    @Test func diagnosticLines() {
        #expect(TartPrerequisiteStatus.ok(
            version: TartVersion(major: 2, minor: 41, patch: 1), binaryPath: "/p", source: .bundled)
            .diagnosticLine == "2.41.1 · bundled · /p")
        #expect(TartPrerequisiteStatus.missing(source: .installed).diagnosticLine
            == "not found · installed")
        #expect(TartPrerequisiteStatus.damaged(source: .bundled, reason: "bad signature")
            .diagnosticLine == "damaged · bundled · bad signature")
        #expect(TartPrerequisiteStatus.invalidCustomPath(path: "/x").diagnosticLine
            == "cannot run · installed · /x")
        #expect(TartPrerequisiteStatus.outdated(
            found: TartVersion(major: 1, minor: 9, patch: 0), required: TartVersion.minimumSupported,
            binaryPath: "/p", source: .installed)
            .diagnosticLine == "1.9.0 (outdated) · installed · /p")
    }

    @Test func statusAccessors() {
        #expect(Self.bundledOk.source == .bundled)
        #expect(Self.bundledOk.version == TartVersion(major: 2, minor: 41, patch: 1))
        #expect(Self.bundledOk.binaryPath == "/b")
        #expect(TartPrerequisiteStatus.invalidCustomPath(path: "/x").source == .installed)
        #expect(TartPrerequisiteStatus.invalidCustomPath(path: "/x").binaryPath == "/x")
        #expect(TartPrerequisiteStatus.missing(source: .bundled).version == nil)
        #expect(TartPrerequisiteStatus.missing(source: .bundled).isSatisfied == false)
    }
}
