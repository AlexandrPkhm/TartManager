import Foundation

/// The user-facing texts of the Replace Disk flow, as pure tested functions:
/// the red data-loss warning (the issue's "red-warning payload" check), the
/// typed-name prompt, and the per-refusal messages presented on the standard
/// sheet (finding 5: refusals are never silent).
public enum ReplaceDiskCopy {
    public static func lossWarning(for vmName: String) -> String {
        "The current disk contents of “\(vmName)” will be lost. "
        + "This includes everything inside the guest — files, apps, and settings."
    }

    public static func confirmPrompt(for vmName: String) -> String {
        "Type “\(vmName)” to confirm"
    }

    public static func refusalMessage(for refusal: ReplaceDiskGuard.Refusal,
                                      vmName: String) -> String {
        switch refusal {
        case .gateFailed:
            return "Replace Disk was not confirmed — nothing was changed."
        case .notLocal:
            return "Only local VMs have replaceable disks — nothing was changed."
        case .running:
            return "“\(vmName)” is running — stop it before replacing its disk."
        case .suspended:
            return "“\(vmName)” is suspended — resume and stop it before replacing its disk."
        case .inFlight:
            return "Another operation is already in progress for “\(vmName)” — "
                + "try again when it finishes."
        }
    }
}
