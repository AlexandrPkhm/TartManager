import Foundation

/// One VM whose fields changed between two snapshots.
public struct VMEntryChange: Equatable, Sendable {
    public let before: VMEntry
    public let after: VMEntry

    public init(before: VMEntry, after: VMEntry) {
        self.before = before
        self.after = after
    }
}

/// Deltas between two `tart list` snapshots, keyed on VM name.
/// Produced by `diff(from:to:)` on every successful poll so the UI state
/// always knows what was added, removed, or changed (PRD Inventory Service:
/// "diffing into UI state").
public struct InventoryDelta: Equatable, Sendable {
    public let added: [VMEntry]
    public let removed: [VMEntry]
    public let changed: [VMEntryChange]

    public init(added: [VMEntry], removed: [VMEntry], changed: [VMEntryChange]) {
        self.added = added
        self.removed = removed
        self.changed = changed
    }

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && changed.isEmpty
    }

    /// Pure, total diff over entry lists. Duplicate names collapse to the
    /// first occurrence (tart enforces name uniqueness per storage anyway).
    public static func diff(from previous: [VMEntry], to current: [VMEntry]) -> InventoryDelta {
        let previousByName = Dictionary(
            previous.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let currentByName = Dictionary(
            current.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let added = current.filter { previousByName[$0.name] == nil }
        let removed = previous.filter { currentByName[$0.name] == nil }
        let changed = current.compactMap { entry -> VMEntryChange? in
            guard let before = previousByName[entry.name], before != entry else { return nil }
            return VMEntryChange(before: before, after: entry)
        }
        return InventoryDelta(
            added: added.sorted { $0.name < $1.name },
            removed: removed.sorted { $0.name < $1.name },
            changed: changed.sorted { $0.after.name < $1.after.name })
    }
}
