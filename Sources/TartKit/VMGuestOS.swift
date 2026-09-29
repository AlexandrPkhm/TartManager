import Foundation

/// Guest-OS facts read from a local VM's on-disk `config.json` (tart 2.32).
/// `tart list` does not report the guest OS, but the per-VM `config.json`
/// records it under the lowercase `os` key with the same literals `tart get`
/// publishes (`"darwin"` | `"linux"`); reading the file directly is a cheap,
/// subprocess-free lookup usable on both the run path and the inventory
/// enrichment path.
///
/// tart only supports suspend/restore for macOS guests: `tart run
/// --suspendable` and `tart suspend` both refuse Linux guests with
/// "You can only suspend macOS VMs" (exit 64). `supportsSuspend` is the
/// single predicate for that restriction.
public enum VMGuestOS {
    /// tart's literal for a macOS guest.
    public static let macOSLiteral = "darwin"

    /// Reads the raw `os` value from `config.json` in the given VM directory
    /// (`$TART_HOME/vms/<name>`). nil when the file is absent/unreadable,
    /// not a JSON object, or the key is missing or mistyped — callers treat
    /// nil as "not known to be macOS", the conservative choice that keeps a
    /// schema drift from reproducing the Linux run refusal.
    public static func read(atVMDirectory directory: String) -> String? {
        guard let data = FileManager.default.contents(atPath: directory + "/config.json"),
              let object = try? JSONSerialization.jsonObject(with: data),
              let config = object as? [String: Any] else { return nil }
        return config["os"] as? String
    }

    /// Whether the guest supports suspend: macOS only. Drives both the
    /// `--suspendable` run flag and the Suspend affordances; nil/unknown is
    /// not macOS. Case-insensitive to match tart's own comparisons.
    public static func supportsSuspend(_ os: String?) -> Bool {
        os?.lowercased() == macOSLiteral
    }
}
