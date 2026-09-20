import Testing
import Foundation
@testable import TartManager

@Suite struct AppIconSourceTests {
    @Test func packagedAppKeepsSystemRenderedDockIcon() {
        #expect(!AppIconSource.needsRuntimeIcon(
            bundleURL: URL(fileURLWithPath: "/Applications/Tart Manager.app")))
    }

    @Test func bareExecutableNeedsRuntimeDockIcon() {
        #expect(AppIconSource.needsRuntimeIcon(
            bundleURL: URL(fileURLWithPath: "/workspace/.build/debug")))
    }

    func makeTempDirectory() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-icon-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: dir.path, withIntermediateDirectories: true)
        return dir.path
    }

    @Test func packagedLayoutListsResourcesIconFirst() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let app = URL(fileURLWithPath: root).appendingPathComponent("Tart Manager.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        let macos = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let icon = resources.appendingPathComponent("AppIcon.icns")
        FileManager.default.createFile(atPath: icon.path, contents: Data("icon".utf8))
        let executable = macos.appendingPathComponent("TartManager")
        FileManager.default.createFile(atPath: executable.path, contents: Data("exe".utf8))

        let candidates = AppIconSource.candidateURLs(resourceURL: resources, executableURL: executable)

        #expect(candidates.first == icon)
    }

    @Test func swiftRunLayoutFindsResourceBundleNextToExecutable() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let binDir = URL(fileURLWithPath: root).appendingPathComponent("debug")
        let bundleResources = binDir
            .appendingPathComponent("TartManager_TartManager.bundle")
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: bundleResources, withIntermediateDirectories: true)
        let icon = bundleResources.appendingPathComponent("AppIcon.icns")
        FileManager.default.createFile(atPath: icon.path, contents: Data("icon".utf8))
        let executable = binDir.appendingPathComponent("TartManager")
        FileManager.default.createFile(atPath: executable.path, contents: Data("exe".utf8))

        let candidates = AppIconSource.candidateURLs(resourceURL: nil, executableURL: executable)

        // Directory enumeration can surface `/var` as `/private/var`; compare
        // symlink-resolved paths.
        #expect(candidates.contains { $0.resolvingSymlinksInPath() == icon.resolvingSymlinksInPath() })
    }

    @Test func adjacentScanIgnoresNonBundleEntries() throws {
        let root = makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let binDir = URL(fileURLWithPath: root)
        let executable = binDir.appendingPathComponent("TartManager")
        FileManager.default.createFile(atPath: executable.path, contents: Data("exe".utf8))
        // Decoys: a plain object file and a directory whose extension is not
        // `.bundle` — neither may yield a candidate.
        FileManager.default.createFile(
            atPath: binDir.appendingPathComponent("TartKit.o").path,
            contents: Data("obj".utf8)
        )
        try FileManager.default.createDirectory(
            at: binDir.appendingPathComponent("TartManagerTests.xctest"),
            withIntermediateDirectories: true
        )

        let candidates = AppIconSource.candidateURLs(resourceURL: nil, executableURL: executable)

        #expect(candidates == [binDir.appendingPathComponent("AppIcon.icns")])
    }

    @Test func emptyWhenNoLocationsProvided() {
        let candidates = AppIconSource.candidateURLs(resourceURL: nil, executableURL: nil)
        #expect(candidates.isEmpty)
    }
}
