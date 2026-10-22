import Testing
@testable import TartKit
@testable import TartManager

@Suite struct TartSourcePromptCopyTests {
    private func copy(bundled: String, installed: String) -> TartSourcePromptCopy {
        TartSourcePromptCopy(report: TartRuntimeReport(
            bundled: .ok(version: TartVersion.parse(bundled)!, binaryPath: "/b", source: .bundled),
            installed: .ok(version: TartVersion.parse(installed)!, binaryPath: "/opt/homebrew/bin/tart",
                           source: .installed),
            selected: .installed, storedPreference: nil))
    }

    @Test func verbatimCopy() {
        let copy = copy(bundled: "2.41.1", installed: "2.32.1")
        #expect(copy.title == "Choose the tart that Tart Manager uses")
        #expect(copy.body == "Tart Manager now includes its own tart. You can also keep the tart that is installed on this Mac. You can change this later in Settings.")
        #expect(copy.bundledLabel == "Bundled with Tart Manager")
        #expect(copy.installedLabel == "Installed on this Mac")
        #expect(copy.keepInstalledButton == "Keep Installed")
        #expect(copy.useBundledButton == "Use Bundled")
    }

    @Test func rowsShowVersionsAndPath() {
        let copy = copy(bundled: "2.41.1", installed: "2.32.1")
        #expect(copy.bundledDetail == "tart 2.41.1")
        #expect(copy.installedDetail == "tart 2.32.1")
        #expect(copy.installedPath == "/opt/homebrew/bin/tart")
    }

    @Test func warningWhenInstalledIsOlder() {
        #expect(copy(bundled: "2.41.1", installed: "2.32.1").warning
            == "The selected tart (2.32.1) is older than the other tart (2.41.1). VMs that the newer tart changed can fail to open.")
    }

    @Test func noWarningWhenInstalledIsNewer() {
        #expect(copy(bundled: "2.41.1", installed: "2.42.0").warning == nil)
    }
}
