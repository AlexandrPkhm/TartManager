import Testing
@testable import TartKit

@Suite struct TartPrerequisiteGuidanceTests {
    private static let bundledOk = TartPrerequisiteStatus.ok(
        version: TartVersion(major: 2, minor: 41, patch: 1), binaryPath: "/b", source: .bundled)
    private static let installedOk = TartPrerequisiteStatus.ok(
        version: TartVersion(major: 2, minor: 32, patch: 1), binaryPath: "/i", source: .installed)
    private static let installedMissing = TartPrerequisiteStatus.missing(source: .installed)
    private static let bundledDamaged = TartPrerequisiteStatus.damaged(source: .bundled, reason: "x")

    private func report(bundled: TartPrerequisiteStatus?, installed: TartPrerequisiteStatus,
                        selected: TartSource) -> TartRuntimeReport {
        TartRuntimeReport(bundled: bundled, installed: installed,
                          selected: selected, storedPreference: selected)
    }

    private func guidance(bundled: TartPrerequisiteStatus?, installed: TartPrerequisiteStatus,
                          selected: TartSource) throws -> TartPrerequisiteGuidanceInfo {
        try #require(TartPrerequisiteGuidance.guidance(
            for: report(bundled: bundled, installed: installed, selected: selected)))
    }

    @Test func okHasNoGuidance() {
        #expect(TartPrerequisiteGuidance.guidance(
            for: report(bundled: Self.bundledOk, installed: Self.installedOk, selected: .bundled)) == nil)
        #expect(TartPrerequisiteGuidance.guidance(
            for: report(bundled: nil, installed: Self.installedOk, selected: .installed)) == nil)
    }

    @Test func bundledMissing() throws {
        let info = try guidance(bundled: nil, installed: Self.installedMissing, selected: .bundled)
        #expect(info.headline == "Bundled tart is missing")
        #expect(info.detail == "Reinstall Tart Manager to restore it.")
        #expect(info.command == nil)
    }

    @Test func bundledDamaged() throws {
        let info = try guidance(bundled: Self.bundledDamaged, installed: Self.installedMissing,
                                selected: .bundled)
        #expect(info.headline == "Bundled tart is damaged")
        #expect(info.detail == "Reinstall Tart Manager to restore it.")
        #expect(info.command == nil)
    }

    @Test func installedMissing() throws {
        let info = try guidance(bundled: nil, installed: Self.installedMissing, selected: .installed)
        #expect(info.headline == "Tart is not installed")
        #expect(info.detail == "Install tart with Homebrew, or choose a tart file in Settings → General:")
        #expect(info.command == TartPrerequisiteGuidance.installCommand)
    }

    @Test func invalidCustomPath() throws {
        let info = try guidance(bundled: nil, installed: .invalidCustomPath(path: "/x"),
                                selected: .installed)
        #expect(info.headline == "The selected tart cannot run")
        #expect(info.detail == "Choose another tart file in Settings → General.")
        #expect(info.command == nil)
    }

    @Test func installedOutdated() throws {
        let status = TartPrerequisiteStatus.outdated(
            found: TartVersion(major: 1, minor: 9, patch: 9), required: TartVersion.minimumSupported,
            binaryPath: "/opt/homebrew/bin/tart", source: .installed)
        let info = try guidance(bundled: nil, installed: status, selected: .installed)
        #expect(info.headline == "Tart is outdated")
        #expect(info.detail
            == "Tart Manager needs tart 2.0.0 or newer; found 1.9.9. Upgrading is recommended:")
        #expect(info.command == TartPrerequisiteGuidance.upgradeCommand)
    }

    @Test func bundledOutdated() throws {
        let status = TartPrerequisiteStatus.outdated(
            found: TartVersion(major: 1, minor: 9, patch: 9), required: TartVersion.minimumSupported,
            binaryPath: "/b", source: .bundled)
        let info = try guidance(bundled: status, installed: Self.installedMissing, selected: .bundled)
        #expect(info.headline == "Tart is outdated")
        #expect(info.detail == "Update Tart Manager to get a newer bundled tart.")
        #expect(info.command == nil)
    }

    @Test func offersSwitchWhenOtherIsOk() throws {
        let toInstalled = try guidance(bundled: Self.bundledDamaged, installed: Self.installedOk,
                                       selected: .bundled)
        #expect(toInstalled.switchTo == .installed)
        let toBundled = try guidance(bundled: Self.bundledOk, installed: Self.installedMissing,
                                     selected: .installed)
        #expect(toBundled.switchTo == .bundled)
    }

    @Test func noSwitchWhenOtherFails() throws {
        let info = try guidance(bundled: Self.bundledDamaged, installed: Self.installedMissing,
                                selected: .bundled)
        #expect(info.switchTo == nil)
        let noBundled = try guidance(bundled: nil, installed: Self.installedMissing, selected: .installed)
        #expect(noBundled.switchTo == nil)
    }

    @Test func switchLabels() {
        #expect(TartPrerequisiteGuidance.switchLabel(for: .bundled) == "Use bundled tart")
        #expect(TartPrerequisiteGuidance.switchLabel(for: .installed) == "Use installed tart")
    }
}
