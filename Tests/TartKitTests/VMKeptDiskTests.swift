import Testing
import Foundation
@testable import TartKit

@Suite struct VMKeptDiskTests {
    /// A `TART_HOME` with one VM that holds a `disk.img`.
    private func makeHome(vm: String = "vm-a", disk: String? = "disk-data") throws -> String {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)").path
        let directory = home + "/vms/" + vm
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        if let disk {
            try disk.write(toFile: directory + "/disk.img", atomically: true, encoding: .utf8)
        }
        return home
    }

    @Test func keptDiskSurvivesTheVMFolderRemoval() throws {
        let home = try makeHome()
        let path = try VMKeptDisk.keep(vmName: "vm-a", environment: ["TART_HOME": home])
        #expect(path == home + "/Kept Disks/vm-a.img")
        try FileManager.default.removeItem(atPath: home + "/vms/vm-a")
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "disk-data")
    }

    @Test func keepLeavesTheVMDiskInPlace() throws {
        let home = try makeHome()
        _ = try VMKeptDisk.keep(vmName: "vm-a", environment: ["TART_HOME": home])
        #expect(FileManager.default.fileExists(atPath: home + "/vms/vm-a/disk.img"))
    }

    @Test func earlierKeptDiskIsNotOverwritten() throws {
        let home = try makeHome()
        let environment = ["TART_HOME": home]
        let first = try VMKeptDisk.keep(vmName: "vm-a", environment: environment)
        try FileManager.default.removeItem(atPath: home + "/vms/vm-a")
        _ = try makeHomeVM(home: home, disk: "new-data")
        let second = try VMKeptDisk.keep(vmName: "vm-a", environment: environment)
        #expect(second == home + "/Kept Disks/vm-a 2.img")
        #expect(try String(contentsOfFile: first, encoding: .utf8) == "disk-data")
        #expect(try String(contentsOfFile: second, encoding: .utf8) == "new-data")
    }

    private func makeHomeVM(home: String, disk: String) throws {
        let directory = home + "/vms/vm-a"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try disk.write(toFile: directory + "/disk.img", atomically: true, encoding: .utf8)
    }

    @Test func missingDiskIsAnError() throws {
        let home = try makeHome(disk: nil)
        #expect(throws: VMKeptDisk.KeepError.noDisk(path: home + "/vms/vm-a/disk.img")) {
            try VMKeptDisk.keep(vmName: "vm-a", environment: ["TART_HOME": home])
        }
    }

    @Test func missingStorageIsAnError() throws {
        #expect(throws: VMKeptDisk.KeepError.noStorage) {
            try VMKeptDisk.keep(vmName: "vm-a", environment: [:])
        }
        let home = try makeHome()
        #expect(throws: VMKeptDisk.KeepError.noStorage) {
            try VMKeptDisk.keep(vmName: "../vm-a", environment: ["TART_HOME": home])
        }
    }

    @Test func discardRemovesOnlyTheKeptDisk() throws {
        let home = try makeHome()
        let path = try VMKeptDisk.keep(vmName: "vm-a", environment: ["TART_HOME": home])
        try VMKeptDisk.discard(path: path)
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(try String(contentsOfFile: home + "/vms/vm-a/disk.img", encoding: .utf8) == "disk-data")
    }

    @Test func folderNeedsTartHome() {
        #expect(VMKeptDisk.folder(environment: [:]) == nil)
        #expect(VMKeptDisk.folder(environment: ["TART_HOME": "/x"]) == "/x/Kept Disks")
    }
}
