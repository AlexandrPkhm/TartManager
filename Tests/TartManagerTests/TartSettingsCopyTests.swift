import Testing
@testable import TartKit
@testable import TartManager

@Suite struct TartSettingsCopyTests {
    private static let v2411 = TartVersion(major: 2, minor: 41, patch: 1)
    private static let v2321 = TartVersion(major: 2, minor: 32, patch: 1)
    private static let bundledOk = TartPrerequisiteStatus.ok(
        version: v2411, binaryPath: "/Applications/Tart Manager.app/tart", source: .bundled)
    private static let detectedOk = TartPrerequisiteStatus.ok(
        version: v2321, binaryPath: "/opt/homebrew/bin/tart", source: .installed)

    private func copy(bundled: TartPrerequisiteStatus? = bundledOk,
                      installed: TartPrerequisiteStatus = detectedOk,
                      selected: TartSource = .installed,
                      customPath: String? = nil,
                      runningJobs: Int = 0) -> TartSettingsCopy {
        TartSettingsCopy(
            report: TartRuntimeReport(bundled: bundled, installed: installed,
                                      selected: selected, storedPreference: selected),
            customPath: customPath, runningJobs: runningJobs)
    }

    @Test func bundledUnavailableCaption() {
        let copy = copy(bundled: nil)
        #expect(copy.bundledEnabled == false)
        #expect(copy.bundledCaption == "Not available in this build")
        #expect(copy.bundledVersionText == nil)
    }

    @Test func bundledVersionShown() {
        let copy = copy()
        #expect(copy.bundledEnabled)
        #expect(copy.bundledCaption == nil)
        #expect(copy.bundledVersionText == "tart 2.41.1")
    }

    @Test func bundledDamagedCaption() {
        let copy = copy(bundled: .damaged(source: .bundled, reason: "x"))
        #expect(copy.bundledEnabled)
        #expect(copy.bundledCaption == "Damaged. Reinstall Tart Manager.")
        #expect(copy.bundledVersionText == nil)
    }

    @Test func detectedPathCaption() {
        let copy = copy()
        #expect(copy.pathFieldValue == "/opt/homebrew/bin/tart")
        #expect(copy.pathCaption.hasPrefix("Detected automatically"))
        #expect(copy.pathCaption.contains("tart 2.32.1"))
        #expect(copy.showsReset == false)
    }

    @Test func customPathCaption() {
        let installed = TartPrerequisiteStatus.ok(version: Self.v2321, binaryPath: "/x/tart",
                                                  source: .installed)
        let copy = copy(installed: installed, customPath: "/x/tart")
        #expect(copy.pathFieldValue == "/x/tart")
        #expect(copy.pathCaption.hasPrefix("Custom path"))
        #expect(copy.pathCaption.contains("tart 2.32.1"))
        #expect(copy.showsReset)
    }

    @Test func notFoundCaption() {
        let copy = copy(installed: .missing(source: .installed))
        #expect(copy.pathFieldValue == "")
        #expect(copy.pathCaption
            == "Not found. Install tart with `brew install cirruslabs/cli/tart` or choose a file.")
    }

    @Test func cannotRunCaption() {
        let copy = copy(installed: .invalidCustomPath(path: "/x/tart"), customPath: "/x/tart")
        #expect(copy.pathFieldValue == "/x/tart")
        #expect(copy.pathCaption.hasPrefix("Custom path"))
        #expect(copy.pathCaption.contains("cannot run"))
        #expect(copy.showsReset)
    }

    @Test func outdatedPathCaption() {
        let installed = TartPrerequisiteStatus.outdated(
            found: TartVersion(major: 1, minor: 9, patch: 0), required: TartVersion.minimumSupported,
            binaryPath: "/opt/homebrew/bin/tart", source: .installed)
        #expect(copy(installed: installed).pathCaption
            == "Detected automatically · tart 1.9.0 (outdated)")
    }

    @Test func pathRowEnabledOnlyForPath() {
        #expect(copy(selected: .installed).pathControlsEnabled)
        #expect(copy(selected: .bundled).pathControlsEnabled == false)
    }

    @Test func jobsDisableControls() {
        let two = copy(runningJobs: 2)
        #expect(two.controlsEnabled == false)
        #expect(two.jobsCaption == "Finish or cancel 2 running jobs to change the tart source.")
        #expect(copy(runningJobs: 1).jobsCaption
            == "Finish or cancel 1 running job to change the tart source.")
        let none = copy(runningJobs: 0)
        #expect(none.controlsEnabled)
        #expect(none.jobsCaption == nil)
    }

    @Test func activeLine() {
        let bundled = copy(selected: .bundled)
        #expect(bundled.activeLine == "2.41.1 · Bundled")
        #expect(bundled.activeHelp == "/Applications/Tart Manager.app/tart")
        #expect(copy(selected: .installed).activeLine == "2.32.1 · Path")
        let missing = copy(bundled: nil, selected: .bundled)
        #expect(missing.activeLine == "Not found · Bundled")
        #expect(missing.activeHelp == nil)
    }

    @Test func rejectionMessages() {
        #expect(TartSettingsCopy.rejectionMessage(.notAbsolute) == "Choose the file by its full path.")
        #expect(TartSettingsCopy.rejectionMessage(.missing) == "The chosen file no longer exists.")
        #expect(TartSettingsCopy.rejectionMessage(.notRegularFile) == "The chosen item is not a file.")
        #expect(TartSettingsCopy.rejectionMessage(.notExecutable) == "The chosen file is not executable.")
    }

    @Test func warningFromSkewPolicy() {
        #expect(copy(selected: .installed).versionWarning
            == "The selected tart (2.32.1) is older than the other tart (2.41.1). VMs that the newer tart changed can fail to open.")
        #expect(copy(selected: .bundled).versionWarning == nil)
    }
}
