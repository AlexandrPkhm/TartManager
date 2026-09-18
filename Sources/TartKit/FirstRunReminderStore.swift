import Foundation

/// One-time first-run reminders for IPSW-created VMs.
///
/// A VM name is flagged when its create-from-IPSW job completes; the first
/// Run of a flagged VM presents the Setup Assistant reminder. The flag is
/// cleared only when the inventory first observes that VM running — so a
/// cancelled reminder or a failed run keeps reminding, and exactly one
/// successful first run makes the reminder one-time. Flags are persisted in
/// UserDefaults (injected for tests) and survive app relaunches.
public struct FirstRunReminderStore: Sendable {
    static let key = "firstRunReminderVMNames"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Flags the VM so its next Run shows the one-time reminder.
    public func flag(_ name: String) {
        var names = flaggedNames
        guard !names.contains(name) else { return }
        names.append(name)
        defaults.set(names, forKey: Self.key)
    }

    /// True while the VM has never been observed running since its IPSW create.
    public func contains(_ name: String) -> Bool {
        flaggedNames.contains(name)
    }

    /// Consumes the reminder for a VM that has now run.
    public func unflag(_ name: String) {
        defaults.set(flaggedNames.filter { $0 != name }, forKey: Self.key)
    }

    /// Drops flags for names no longer present in the inventory (deleted VMs
    /// must not accumulate stale reminders).
    public func prune(keeping liveNames: Set<String>) {
        defaults.set(flaggedNames.filter { liveNames.contains($0) }, forKey: Self.key)
    }

    private var flaggedNames: [String] {
        defaults.stringArray(forKey: Self.key) ?? []
    }
}
