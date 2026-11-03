import Foundation

/// Saves a VM's disk image before `tart delete` removes the VM folder.
///
/// The kept disk is a hard link in `$TART_HOME/Kept Disks`. A hard link needs
/// no copy and no extra space. The folder is in `TART_HOME`, so it is on the
/// same volume as the VM. A file system without hard links fails the keep
/// before the delete starts.
///
/// Only a standalone VM has a disk that works alone. A stacked VM has
/// `overlay.asif` and shared base images and no `disk.img`, so linking its
/// overlay would not keep a usable disk. The layout rule follows tart's
/// `VMDirectory.layout`.
public enum VMKeptDisk {
    public static let folderName = "Kept Disks"
    static let diskFilename = "disk.img"
    static let overlayFilename = "overlay.asif"

    public enum KeepError: Error, Equatable, Sendable, CustomStringConvertible {
        case noStorage
        case notStandalone

        public var description: String {
            switch self {
            case .noStorage: return "the VM folder is not available."
            case .notStandalone: return "this VM does not have a standalone disk."
            }
        }
    }

    /// The folder for kept disks, or nil when `TART_HOME` is absent from the
    /// injected environment.
    public static func folder(environment: [String: String]) -> String? {
        environment["TART_HOME"].map {
            ($0 as NSString).appendingPathComponent(folderName)
        }
    }

    /// `true` when the VM has a standalone disk that `keep` can save.
    public static func canKeep(vmName: String, environment: [String: String]) -> Bool {
        guard let directory = TartClient.vmStoragePath(environment: environment, name: vmName) else {
            return false
        }
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: path(directory, diskFilename))
            && !fileManager.fileExists(atPath: path(directory, overlayFilename))
    }

    /// Links the VM's disk as `<folder>/<name>.img` and returns that path.
    /// An earlier kept disk with the same name stays: the new one gets a
    /// number, for example `<name> 2.img`.
    public static func keep(vmName: String, environment: [String: String]) throws -> String {
        guard let folder = folder(environment: environment),
              let directory = TartClient.vmStoragePath(environment: environment, name: vmName) else {
            throw KeepError.noStorage
        }
        guard canKeep(vmName: vmName, environment: environment) else {
            throw KeepError.notStandalone
        }
        let disk = path(directory, diskFilename)
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let destination = availablePath(in: folder, vmName: vmName)
        try fileManager.linkItem(atPath: disk, toPath: destination)
        return destination
    }

    /// Removes a kept disk after a failed delete, only when the VM folder
    /// still holds the same file, and returns `true` when it removed it.
    ///
    /// `tart delete` is not transactional: a failure can occur after it
    /// removed `disk.img`, and the VM can still show in `tart list`. The file
    /// identity is the only proof that the kept disk is not the last copy.
    /// A file that is missing or different leaves the kept disk in place.
    public static func discardIfOriginalRemains(keptPath: String, vmName: String,
                                                environment: [String: String]) throws -> Bool {
        guard let directory = TartClient.vmStoragePath(environment: environment, name: vmName) else {
            return false
        }
        let fileManager = FileManager.default
        guard let original = try? fileManager.attributesOfItem(atPath: path(directory, diskFilename)),
              let kept = try? fileManager.attributesOfItem(atPath: keptPath),
              let originalFile = original[.systemFileNumber] as? NSNumber,
              let keptFile = kept[.systemFileNumber] as? NSNumber,
              let originalVolume = original[.systemNumber] as? NSNumber,
              let keptVolume = kept[.systemNumber] as? NSNumber,
              originalFile == keptFile, originalVolume == keptVolume else {
            return false
        }
        try fileManager.removeItem(atPath: keptPath)
        return true
    }

    private static func path(_ directory: String, _ filename: String) -> String {
        (directory as NSString).appendingPathComponent(filename)
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
