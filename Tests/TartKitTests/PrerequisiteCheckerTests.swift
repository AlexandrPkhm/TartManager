import Testing
import Foundation
@testable import TartKit

@Suite struct PrerequisiteCheckerTests {
    private static let v2411 = TartVersion(major: 2, minor: 41, patch: 1)
    private static let v2400 = TartVersion(major: 2, minor: 40, patch: 0)
    private static let v2321 = TartVersion(major: 2, minor: 32, patch: 1)

    private func makeChecker(
        bundled: String? = nil,
        wellKnown: [String] = [],
        verification: BundledTartVerification = .valid,
        minimumVersion: TartVersion = TartVersion.minimumSupported
    ) -> PrerequisiteChecker {
        PrerequisiteChecker(
            bundledExecutablePath: bundled,
            locator: TartLocator(searchPath: "", wellKnownLocations: wellKnown),
            verify: { _ in verification },
            minimumVersion: minimumVersion)
    }

    private func preference(_ source: TartSource?, customPath: String? = nil) -> TartSourcePreference {
        TartSourcePreference(source: source, customPath: customPath)
    }

    // MARK: Bundled source

    @Test func bundledSelectedAndValid() {
        let bundled = StubBinary.tartVersionStub(output: "2.41.1")
        let report = makeChecker(bundled: bundled).check(preference: preference(.bundled))
        #expect(report.active == .ok(version: Self.v2411, binaryPath: bundled, source: .bundled))
    }

    @Test func bundledVerificationFailureIsDamaged() {
        let stub = StubBinary.makeRecordingStub()
        let report = makeChecker(bundled: stub.stubPath, verification: .damaged(reason: "x"))
            .check(preference: preference(.bundled))
        #expect(report.bundled == .damaged(source: .bundled, reason: "x"))
        #expect(!FileManager.default.fileExists(atPath: stub.invocationFile))
    }

    @Test func bundledVersionFailureIsDamaged() {
        let bundled = StubBinary.make(script: "#!/bin/sh\nexit 1\n")
        let report = makeChecker(bundled: bundled).check(preference: preference(.bundled))
        guard case .damaged(.bundled, _)? = report.bundled else {
            Issue.record("expected a damaged bundled tart, got \(String(describing: report.bundled))")
            return
        }
    }

    @Test func noBundledPathReportsNilBundled() {
        let report = makeChecker(bundled: nil).check(preference: preference(.bundled))
        #expect(report.bundled == nil)
        #expect(report.active == .missing(source: .bundled))
    }

    @Test func bundledSelectedNeverFallsBack() {
        let bundled = StubBinary.tartVersionStub(output: "2.41.1")
        let installed = StubBinary.tartVersionStub(output: "2.32.1")
        let report = makeChecker(bundled: bundled, wellKnown: [installed],
                                 verification: .damaged(reason: "bad"))
            .check(preference: preference(.bundled))
        #expect(report.active == .damaged(source: .bundled, reason: "bad"))
        #expect(report.installed == .ok(version: Self.v2321, binaryPath: installed, source: .installed))
    }

    // MARK: Installed source

    @Test func customPathWinsOverDetection() {
        let custom = StubBinary.tartVersionStub(output: "2.40.0")
        let detected = StubBinary.tartVersionStub(output: "2.32.1")
        let report = makeChecker(wellKnown: [detected])
            .check(preference: preference(.installed, customPath: custom))
        #expect(report.installed == .ok(version: Self.v2400, binaryPath: custom, source: .installed))
    }

    @Test func invalidCustomPathReportsInvalid() {
        let detected = StubBinary.tartVersionStub(output: "2.32.1")
        let report = makeChecker(wellKnown: [detected])
            .check(preference: preference(.installed, customPath: "/nonexistent/tart"))
        #expect(report.installed == .invalidCustomPath(path: "/nonexistent/tart"))
    }

    @Test func customPathVersionFailureIsInvalid() {
        let custom = StubBinary.make(script: "#!/bin/sh\nexit 1\n")
        let report = makeChecker().check(preference: preference(.installed, customPath: custom))
        #expect(report.installed == .invalidCustomPath(path: custom))
    }

    @Test func detectedInstalledMissing() {
        let report = makeChecker(wellKnown: ["/nonexistent/tart"])
            .check(preference: preference(.installed))
        #expect(report.installed == .missing(source: .installed))
    }

    @Test func installedOutdated() {
        let detected = StubBinary.tartVersionStub(output: "1.9.0")
        let report = makeChecker(wellKnown: [detected]).check(preference: preference(.installed))
        #expect(report.installed == .outdated(
            found: TartVersion(major: 1, minor: 9, patch: 0),
            required: TartVersion.minimumSupported,
            binaryPath: detected, source: .installed))
    }

    @Test func nilPreferenceSelectsInstalled() {
        let report = makeChecker().check(preference: preference(nil))
        #expect(report.selected == .installed)
        #expect(report.storedPreference == nil)
    }

    @Test func storedPreferenceIsRecorded() {
        let report = makeChecker().check(preference: preference(.bundled))
        #expect(report.storedPreference == .bundled)
        #expect(report.selected == .bundled)
    }

    // MARK: Version parsing (installed source)

    @Test func reportsOkForEqualsBoundary() {
        let stub = StubBinary.tartVersionStub(output: "\(TartVersion.minimumSupported)")
        let report = makeChecker(wellKnown: [stub]).check(preference: preference(.installed))
        if case .ok = report.installed {} else {
            Issue.record("expected .ok at the minimum boundary")
        }
    }

    @Test func respectsInjectedMinimumVersion() {
        let stub = StubBinary.tartVersionStub(output: "2.5.0")
        let required = TartVersion(major: 3, minor: 0, patch: 0)
        let report = makeChecker(wellKnown: [stub], minimumVersion: required)
            .check(preference: preference(.installed))
        #expect(report.installed == .outdated(found: TartVersion(major: 2, minor: 5, patch: 0),
                                              required: required, binaryPath: stub,
                                              source: .installed))
    }

    @Test func reportsMissingWhenOutputUnparseable() {
        let stub = StubBinary.tartVersionStub(output: "slartibartfast")
        let report = makeChecker(wellKnown: [stub]).check(preference: preference(.installed))
        #expect(report.installed == .missing(source: .installed))
    }

    @Test func reportsMissingWhenVersionExitsNonZero() {
        let stub = StubBinary.make(script: "#!/bin/sh\nexit 2\n")
        let report = makeChecker(wellKnown: [stub]).check(preference: preference(.installed))
        #expect(report.installed == .missing(source: .installed))
    }

    @Test func reportsMissingWhenBinaryCannotBeLaunched() {
        // Executable bits set, but the interpreter is missing: locate()
        // accepts the path, Process.run() throws.
        let stub = StubBinary.make(script: "#!/nonexistent/interpreter\n")
        let report = makeChecker(wellKnown: [stub]).check(preference: preference(.installed))
        #expect(report.installed == .missing(source: .installed))
    }
}
