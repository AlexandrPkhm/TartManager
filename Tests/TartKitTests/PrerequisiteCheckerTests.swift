import Testing
import Foundation
@testable import TartKit

@Suite struct PrerequisiteCheckerTests {
    @Test func reportsOkForSufficientVersion() {
        let stub = StubBinary.tartVersionStub(output: "2.32.0")
        let checker = PrerequisiteChecker(
            locator: TartLocator(explicitPath: stub, searchPath: "", wellKnownLocations: []))
        let status = checker.check()
        #expect(status == .ok(version: TartVersion(major: 2, minor: 32, patch: 0), binaryPath: stub))
    }

    @Test func reportsOutdatedForOlderVersion() {
        let stub = StubBinary.tartVersionStub(output: "1.0.0")
        let checker = PrerequisiteChecker(
            locator: TartLocator(explicitPath: stub, searchPath: "", wellKnownLocations: []))
        #expect(checker.check() == .outdated(found: TartVersion(major: 1, minor: 0, patch: 0),
                                             required: TartVersion.minimumSupported,
                                             binaryPath: stub))
    }

    @Test func reportsOkForEqualsBoundary() {
        // Exactly the minimum is OK, not outdated.
        let floor = TartVersion.minimumSupported
        let stub = StubBinary.tartVersionStub(output: "\(floor)")
        let checker = PrerequisiteChecker(
            locator: TartLocator(explicitPath: stub, searchPath: "", wellKnownLocations: []))
        if case .ok = checker.check() {} else {
            Issue.record("expected .ok at the minimum boundary")
        }
    }

    @Test func respectsInjectedMinimumVersion() {
        let stub = StubBinary.tartVersionStub(output: "2.5.0")
        let checker = PrerequisiteChecker(
            locator: TartLocator(explicitPath: stub, searchPath: "", wellKnownLocations: []),
            minimumVersion: TartVersion(major: 3, minor: 0, patch: 0))
        #expect(checker.check() == .outdated(found: TartVersion(major: 2, minor: 5, patch: 0),
                                             required: TartVersion(major: 3, minor: 0, patch: 0),
                                             binaryPath: stub))
    }

    @Test func reportsMissingWhenBinaryAbsent() {
        let checker = PrerequisiteChecker(
            locator: TartLocator(explicitPath: "/nonexistent/tart", searchPath: "", wellKnownLocations: []))
        #expect(checker.check() == .missing)
    }

    @Test func reportsMissingWhenOutputUnparseable() {
        let stub = StubBinary.tartVersionStub(output: "slartibartfast")
        let checker = PrerequisiteChecker(
            locator: TartLocator(explicitPath: stub, searchPath: "", wellKnownLocations: []))
        #expect(checker.check() == .missing)
    }

    @Test func reportsMissingWhenVersionExitsNonZero() {
        let stub = StubBinary.make(script: "#!/bin/sh\nexit 2\n")
        let checker = PrerequisiteChecker(
            locator: TartLocator(explicitPath: stub, searchPath: "", wellKnownLocations: []))
        #expect(checker.check() == .missing)
    }

    @Test func reportsMissingWhenBinaryCannotBeLaunched() {
        // Executable bits set, but the interpreter is missing: locate()
        // accepts the path, Process.run() throws.
        let stub = StubBinary.make(script: "#!/nonexistent/interpreter\n")
        let checker = PrerequisiteChecker(
            locator: TartLocator(explicitPath: stub, searchPath: "", wellKnownLocations: []))
        #expect(checker.check() == .missing)
    }
}
