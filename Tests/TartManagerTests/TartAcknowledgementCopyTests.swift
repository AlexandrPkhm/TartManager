import Testing
@testable import TartKit
@testable import TartManager

@Suite struct TartAcknowledgementCopyTests {
    private static let installed = TartPrerequisiteStatus.ok(
        version: TartVersion(major: 2, minor: 32, patch: 1),
        binaryPath: "/opt/homebrew/bin/tart", source: .installed)
    private static let licensePath = "/Applications/Tart Manager.app/Contents/Resources/tart-LICENSE.txt"

    private func copy(bundled: TartPrerequisiteStatus?,
                      licensePath: String? = licensePath) -> TartAcknowledgementCopy {
        TartAcknowledgementCopy(
            report: TartRuntimeReport(bundled: bundled, installed: Self.installed,
                                      selected: .installed, storedPreference: .installed),
            licensePath: licensePath)
    }

    @Test func showsVersionFromBundledStatus() {
        let bundled = TartPrerequisiteStatus.ok(
            version: TartVersion(major: 2, minor: 41, patch: 1),
            binaryPath: "/Applications/Tart Manager.app/Contents/Helpers/tart.app/Contents/MacOS/tart",
            source: .bundled)
        let copy = copy(bundled: bundled)
        #expect(copy.isVisible)
        #expect(copy.title == "Acknowledgements")
        #expect(copy.line ==
            "Tart Manager includes tart 2.41.1 by Cirrus Labs and OpenAI, under the FSL-1.1-ALv2 license.")
        #expect(copy.showsViewLicense)
        #expect(copy.licensePath == Self.licensePath)
        #expect(copy.viewLicenseButton == "View License")
        #expect(copy.gitHubLinkTitle == "Tart on GitHub")
        #expect(copy.gitHubURL.absoluteString == "https://github.com/openai/tart")
    }

    @Test func hiddenWithoutBundledTart() {
        #expect(copy(bundled: nil).isVisible == false)
        #expect(TartAcknowledgementCopy(report: nil, licensePath: Self.licensePath).isVisible == false)
    }

    @Test func noViewLicenseWithoutFile() {
        let bundled = TartPrerequisiteStatus.ok(
            version: TartVersion(major: 2, minor: 41, patch: 1), binaryPath: "/x/tart", source: .bundled)
        let copy = copy(bundled: bundled, licensePath: nil)
        #expect(copy.isVisible)
        #expect(copy.showsViewLicense == false)
        #expect(copy.line.contains("tart 2.41.1"))
    }

    @Test func damagedBundledStillAcknowledges() {
        let copy = copy(bundled: .damaged(source: .bundled, reason: "unsigned"))
        #expect(copy.isVisible)
        #expect(copy.line ==
            "Tart Manager includes tart by Cirrus Labs and OpenAI, under the FSL-1.1-ALv2 license.")
    }
}
