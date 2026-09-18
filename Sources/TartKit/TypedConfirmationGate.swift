import Foundation

/// The typed-name confirmation rule for destructive operations, as a pure
/// tested function (PRD SC-006). The delete sheet's Delete button AND
/// `AppModel.startDelete`'s boundary re-verification both use this rule —
/// exact string equality, so case and whitespace differences are refused.
/// Issue 15's `RestoreGate` merged with the identical rule, so this gate
/// delegates to it: one implementation owns the rule.
public enum TypedConfirmationGate {
    public static func allowsProceed(typedName: String, vmName: String) -> Bool {
        RestoreGate.allowsProceed(typedName: typedName, vmName: vmName)
    }
}
