import Testing
import Foundation
@testable import TartKit

@Suite struct BundledTartLocationTests {
    private func makeAppBundle() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)")
            .appendingPathComponent("X.app")
        try! FileManager.default.createDirectory(
            at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        return url
    }

    private func writeTart(in bundle: URL, permissions: Int) -> String {
        let path = bundle.appendingPathComponent(BundledTartLocation.relativeExecutablePath).path
        try! FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! "#!/bin/sh\necho 2.41.1\n".write(toFile: path, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
        return path
    }

    @Test func findsExecutableInsideAppBundle() {
        let bundle = makeAppBundle()
        let path = writeTart(in: bundle, permissions: 0o755)
        #expect(BundledTartLocation.executablePath(inAppBundle: bundle) == path)
    }

    @Test func returnsNilWithoutHelpers() {
        #expect(BundledTartLocation.executablePath(inAppBundle: makeAppBundle()) == nil)
    }

    @Test func returnsNilForNonExecutable() {
        let bundle = makeAppBundle()
        _ = writeTart(in: bundle, permissions: 0o644)
        #expect(BundledTartLocation.executablePath(inAppBundle: bundle) == nil)
    }

    @Test func findsLicenseInsideAppBundle() {
        let bundle = makeAppBundle()
        let path = bundle.appendingPathComponent(BundledTartLocation.relativeLicensePath).path
        try! FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try! "license\n".write(toFile: path, atomically: true, encoding: .utf8)
        #expect(BundledTartLocation.licensePath(inAppBundle: bundle) == path)
    }

    @Test func licenseIsNilWithoutFile() {
        #expect(BundledTartLocation.licensePath(inAppBundle: makeAppBundle()) == nil)
    }
}
