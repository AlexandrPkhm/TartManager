/// The delete sheet's copy, derived from the disk choice, so tests cover it
/// without the view.
struct DeleteVMCopy: Equatable {
    static let removeDiskLabel = "Remove the VM disk with the VM"
    static let cannotKeepCaption = "Tart Manager can keep only a standalone disk. This VM does not have one."

    let warning: String
    /// Says where a kept disk goes, or why this VM's disk cannot stay.
    let diskCaption: String?

    init(removeDisk: Bool, canKeepDisk: Bool, keptDisksFolder: String?) {
        let snapshots = "Snapshots in the snapshots folder are not removed."
        if !canKeepDisk {
            warning = "This permanently removes the VM and all of its data. " + snapshots
            diskCaption = Self.cannotKeepCaption
        } else if removeDisk {
            warning = "This permanently removes the VM and all of its data. " + snapshots
            diskCaption = nil
        } else {
            warning = "This permanently removes the VM. Its disk stays as a file. " + snapshots
            diskCaption = keptDisksFolder.map { "The disk goes to \($0)." }
        }
    }
}
