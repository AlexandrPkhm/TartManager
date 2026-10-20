import TartKit

/// The reason-specific text for `StorageUnavailableView`. Kept apart from the
/// view so each `StorageUnavailableReason` maps to tested copy.
struct StorageUnavailableCopy: Equatable {
    /// Text above the storage path that names the cause.
    let headline: String
    /// Text below the storage path that tells the person what to do.
    let hint: String

    static let title = "VM storage unavailable"
    /// `StorageRecheckTimer` re-probes storage, so the screen clears itself.
    static let autoRetryNote =
        "Tart Manager checks again every \(Int(StorageRecheckTimer.defaultInterval)) seconds."

    init(reason: StorageUnavailableReason) {
        switch reason {
        case .missing:
            headline = "The folder or its volume can't be found."
            hint = "Mount the volume, or choose another folder."
        case .notWritable:
            headline = "The folder exists, but Tart Manager can't write to it."
            hint = "Fix the folder's permissions, or choose another folder."
        }
    }
}
