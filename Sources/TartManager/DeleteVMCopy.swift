/// The delete sheet's copy, derived from the disk choice, so tests cover it
/// without the view.
struct DeleteVMCopy: Equatable {
    static let removeDiskLabel = "Remove the VM disk with the VM"

    let warning: String
    /// Says where a kept disk goes; `nil` while the disk is removed.
    let keptDiskCaption: String?

    init(removeDisk: Bool, keptDisksFolder: String?) {
        let snapshots = "Snapshots in the snapshots folder are not removed."
        if removeDisk {
            warning = "This permanently removes the VM and all of its data. " + snapshots
            keptDiskCaption = nil
        } else {
            warning = "This permanently removes the VM. Its disk stays as a file. " + snapshots
            keptDiskCaption = keptDisksFolder.map { "The disk goes to \($0)." }
        }
    }
}
