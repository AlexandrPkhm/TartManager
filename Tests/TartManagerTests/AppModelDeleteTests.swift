import Testing
import Foundation
@testable import TartKit
@testable import TartManager

/// `AppModel.startDelete` end to end with a fake tart that removes the VM
/// folder, as `tart delete` does.
@Suite @MainActor struct AppModelDeleteTests {
    struct Fixture {
        let model: AppModel
        let home: String
    }

    private func makeFixture() throws -> Fixture {
        let suite = "AppModelDeleteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)").path
        let home = root + "/home"
        try FileManager.default.createDirectory(atPath: home + "/vms/vm-a",
                                                withIntermediateDirectories: true)
        try "disk-data".write(toFile: home + "/vms/vm-a/disk.img", atomically: true, encoding: .utf8)
        settings.storagePath = home
        settings.cachePrunePolicy = .manual

        let tart = root + "/tart"
        let script = """
        #!/bin/sh
        if [ "$1" = "list" ]; then
          if [ -d "$TART_HOME/vms/vm-a" ]; then
            echo '[{"Name":"vm-a","Source":"local","Running":false,"State":"stopped","Disk":50,"Size":37}]'
          else
            echo '[]'
          fi
          exit 0
        fi
        if [ "$1" = "delete" ]; then rm -rf "$TART_HOME/vms/$2"; fi
        exit 0
        """
        try script.write(toFile: tart, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tart)

        let model = AppModel(settings: settings, updater: FakeUpdater())
        model.prerequisite = .ok(version: TartVersion(major: 2, minor: 41, patch: 1),
                                 binaryPath: tart, source: .bundled)
        return Fixture(model: model, home: home)
    }

    private let vm = VMEntry(name: "vm-a", source: "local", running: false, state: "stopped",
                             diskSize: 50, diskUsage: 37, accessed: nil)

    @Test func removeDiskLeavesNoFile() async throws {
        let fixture = try makeFixture()
        #expect(fixture.model.startDelete(vm: vm, removeDisk: true) != nil)
        await fixture.model.jobManager.awaitIdle(timeout: 10)
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/vms/vm-a"))
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/Kept Disks"))
    }

    @Test func keepDiskLeavesTheDiskInTheKeptFolder() async throws {
        let fixture = try makeFixture()
        #expect(fixture.model.keptDisksFolder == fixture.home + "/Kept Disks")
        #expect(fixture.model.startDelete(vm: vm, removeDisk: false) != nil)
        await fixture.model.jobManager.awaitIdle(timeout: 10)
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/vms/vm-a"))
        let kept = try String(contentsOfFile: fixture.home + "/Kept Disks/vm-a.img", encoding: .utf8)
        #expect(kept == "disk-data")
    }

    @Test func stackedVMOffersNoKeepAndARefusedKeepLeavesTheVM() async throws {
        let fixture = try makeFixture()
        let directory = fixture.home + "/vms/vm-a"
        #expect(fixture.model.canKeepDisk(vm: vm))
        try FileManager.default.removeItem(atPath: directory + "/disk.img")
        try "overlay".write(toFile: directory + "/overlay.asif", atomically: true, encoding: .utf8)
        #expect(!fixture.model.canKeepDisk(vm: vm))

        #expect(fixture.model.startDelete(vm: vm, removeDisk: false) != nil)
        await fixture.model.jobManager.awaitIdle(timeout: 10)
        #expect(FileManager.default.fileExists(atPath: directory + "/overlay.asif"))
    }

    @Test func runningVMIsRefused() throws {
        let fixture = try makeFixture()
        let running = VMEntry(name: "vm-a", source: "local", running: true, state: "running",
                              diskSize: 50, diskUsage: 37, accessed: nil)
        #expect(fixture.model.startDelete(vm: running, removeDisk: true) == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.home + "/vms/vm-a/disk.img"))
    }
}
