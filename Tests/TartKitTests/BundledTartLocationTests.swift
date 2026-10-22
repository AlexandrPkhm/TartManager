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

    private func writeTartInfo(in bundle: URL, version: String) {
        let url = bundle.appendingPathComponent(BundledTartLocation.relativeInfoPlistPath)
        try! FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let info: NSDictionary = ["CFBundleShortVersionString": version]
        try! info.write(to: url)
    }

    @Test func readsVersionFromTartInfoPlist() {
        let bundle = makeAppBundle()
        writeTartInfo(in: bundle, version: "2.41.1")
        #expect(BundledTartLocation.declaredVersion(inAppBundle: bundle) == "2.41.1")
    }

    @Test func versionIsNilWithoutInfoPlist() {
        #expect(BundledTartLocation.declaredVersion(inAppBundle: makeAppBundle()) == nil)
    }

    @Test func versionIsNilWhenNotXYZ() {
        let bundle = makeAppBundle()
        writeTartInfo(in: bundle, version: "2.41.1/../../evil")
        #expect(BundledTartLocation.declaredVersion(inAppBundle: bundle) == nil)
    }
}
