import Foundation

/// The typed-name confirmation rule for destructive operations, as a pure
/// tested function. The restore sheet's Restore button is enabled only when
/// this holds — exact equality, so case and whitespace differences are
/// refused.
public enum RestoreGate {
    public static func allowsProceed(typedName: String, vmName: String) -> Bool {
        typedName == vmName
    }
}
