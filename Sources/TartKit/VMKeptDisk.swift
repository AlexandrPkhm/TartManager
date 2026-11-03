import Foundation

/// Saves a VM's disk image before `tart delete` removes the VM folder.
///
/// The kept disk is a hard link in `$TART_HOME/Kept Disks`. A hard link needs
/// no copy and no extra space, and the VM folder does not change, so a failed
/// delete leaves the VM intact. The folder is in `TART_HOME`, so it is on the
/// same volume as the VM. A file system without hard links fails the keep
/// before the delete starts.
public enum VMKeptDisk {
    public static let folderName = "Kept Disks"
    static let diskFilename = "disk.img"

    public enum KeepError: Error, Equatable, Sendable {
        case noStorage
        case noDisk(path: String)
    }

    /// The folder for kept disks, or nil when `TART_HOME` is absent from the
    /// injected environment.
    public static func folder(environment: [String: String]) -> String? {
        environment["TART_HOME"].map {
            ($0 as NSString).appendingPathComponent(folderName)
        }
    }

    /// Links the VM's disk as `<folder>/<name>.img` and returns that path.
    /// An earlier kept disk with the same name stays: the new one gets a
    /// number, for example `<name> 2.img`.
    public static func keep(vmName: String, environment: [String: String]) throws -> String {
        guard let folder = folder(environment: environment),
              let directory = TartClient.vmStoragePath(environment: environment, name: vmName) else {
            throw KeepError.noStorage
        }
        let disk = (directory as NSString).appendingPathComponent(diskFilename)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: disk) else {
            throw KeepError.noDisk(path: disk)
        }
        try fileManager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let destination = availablePath(in: folder, vmName: vmName)
        try fileManager.linkItem(atPath: disk, toPath: destination)
        return destination
    }

    /// Removes a kept disk. The caller uses this only after a failed delete,
    /// when the VM folder still holds the disk.
    public static func discard(path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    private static func availablePath(in folder: String, vmName: String) -> String {
        let fileManager = FileManager.default
        var candidate = (folder as NSString).appendingPathComponent("\(vmName).img")
        var number = 2
        while fileManager.fileExists(atPath: candidate) {
            candidate = (folder as NSString).appendingPathComponent("\(vmName) \(number).img")
            number += 1
        }
        return candidate
    }
}
