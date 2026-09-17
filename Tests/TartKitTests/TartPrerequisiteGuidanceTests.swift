import Testing
@testable import TartKit

@Suite struct TartPrerequisiteGuidanceTests {
    @Test func missingYieldsInstallGuidance() throws {
        let info = try #require(TartPrerequisiteGuidance.guidance(for: .missing))
        #expect(info.command == "brew install cirruslabs/cli/tart")
        #expect(info.headline.contains("Tart"))
        #expect(info.detail.contains("Install"))
    }

    @Test func outdatedYieldsUpgradeGuidanceMentioningVersions() throws {
        let status = TartPrerequisiteStatus.outdated(
            found: TartVersion(major: 1, minor: 9, patch: 9),
            required: TartVersion.minimumSupported,
            binaryPath: "/opt/homebrew/bin/tart")
        let info = try #require(TartPrerequisiteGuidance.guidance(for: status))
        #expect(info.command == "brew upgrade cirruslabs/cli/tart")
        #expect(info.detail.contains("1.9.9"))
        #expect(info.detail.contains("2.0.0"))
    }

    @Test func okYieldsNoGuidance() {
        let status = TartPrerequisiteStatus.ok(
            version: TartVersion(major: 2, minor: 32, patch: 0),
            binaryPath: "/opt/homebrew/bin/tart")
        #expect(TartPrerequisiteGuidance.guidance(for: status) == nil)
    }
}
