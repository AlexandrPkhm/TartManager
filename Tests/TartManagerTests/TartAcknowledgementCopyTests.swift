import Testing
@testable import TartKit
@testable import TartManager

@Suite struct TartAcknowledgementCopyTests {
    private static let installed = TartPrerequisiteStatus.ok(
        version: TartVersion(major: 2, minor: 32, patch: 1),
        binaryPath: "/opt/homebrew/bin/tart", source: .installed)
    private static let bundledOk = TartPrerequisiteStatus.ok(
        version: TartVersion(major: 2, minor: 41, patch: 1),
        binaryPath: "/Applications/Tart Manager.app/Contents/Helpers/tart.app/Contents/MacOS/tart",
        source: .bundled)

    private func copy(bundled: TartPrerequisiteStatus?,
                      bundledVersion: String?) -> TartAcknowledgementCopy {
        TartAcknowledgementCopy(
            report: TartRuntimeReport(bundled: bundled, installed: Self.installed,
                                      selected: .installed, storedPreference: .installed),
            bundledVersion: bundledVersion)
    }

    @Test func showsVersionAndLinksToItsLicense() {
        let copy = copy(bundled: Self.bundledOk, bundledVersion: "2.41.1")
        #expect(copy.isVisible)
        #expect(copy.title == "Acknowledgements")
        #expect(copy.line ==
            "Tart Manager includes tart 2.41.1 by Cirrus Labs and OpenAI, under the FSL-1.1-ALv2 license.")
        #expect(copy.viewLicenseButton == "View License")
        #expect(copy.licenseURL.absoluteString == "https://github.com/openai/tart/blob/2.41.1/LICENSE")
        #expect(copy.gitHubLinkTitle == "Tart on GitHub")
        #expect(copy.gitHubURL.absoluteString == "https://github.com/openai/tart")
    }

    @Test func hiddenWithoutBundledTart() {
        #expect(copy(bundled: nil, bundledVersion: nil).isVisible == false)
        #expect(TartAcknowledgementCopy(report: nil, bundledVersion: nil).isVisible == false)
    }

    @Test func checkedVersionIsUsedWhenTheBundleDeclaresNone() {
        let copy = copy(bundled: Self.bundledOk, bundledVersion: nil)
        #expect(copy.line.contains("tart 2.41.1"))
        #expect(copy.licenseURL.absoluteString == "https://github.com/openai/tart/blob/2.41.1/LICENSE")
    }

    @Test func damagedBundledUsesTheDeclaredVersion() {
        let copy = copy(bundled: .damaged(source: .bundled, reason: "unsigned"), bundledVersion: "2.41.1")
        #expect(copy.isVisible)
        #expect(copy.line.contains("tart 2.41.1"))
        #expect(copy.licenseURL.absoluteString == "https://github.com/openai/tart/blob/2.41.1/LICENSE")
    }

    @Test func unknownVersionLinksToTheCurrentLicense() {
        let copy = copy(bundled: .damaged(source: .bundled, reason: "unsigned"), bundledVersion: nil)
        #expect(copy.line ==
            "Tart Manager includes tart by Cirrus Labs and OpenAI, under the FSL-1.1-ALv2 license.")
        #expect(copy.licenseURL.absoluteString == "https://github.com/openai/tart/blob/main/LICENSE")
    }
}
