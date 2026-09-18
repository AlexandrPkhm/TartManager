import Testing
import Foundation
@testable import TartKit

@Suite struct InventoryDeltaTests {
    func entry(_ name: String, source: String = "local",
               running: Bool = false, state: String = "stopped") -> VMEntry {
        VMEntry(name: name, source: source, running: running, state: state,
                diskSize: 0, diskUsage: 0, accessed: nil)
    }

    @Test func diffDetectsAddedRemovedAndChanged() {
        let previous = [entry("keep"), entry("gone"), entry("img:1", source: "oci")]
        let current = [entry("keep", running: true, state: "running"), entry("new")]

        let delta = InventoryDelta.diff(from: previous, to: current)
        #expect(delta.added.map(\.name) == ["new"])
        #expect(delta.removed.map(\.name) == ["gone", "img:1"])
        #expect(delta.changed.count == 1)
        #expect(delta.changed[0].before.state == "stopped")
        #expect(delta.changed[0].after.state == "running")
        #expect(!delta.isEmpty)
    }

    @Test func diffFromNothingAddsEverything() {
        let current = [entry("a"), entry("b")]
        let delta = InventoryDelta.diff(from: [], to: current)
        #expect(delta.added.map(\.name) == ["a", "b"])
        #expect(delta.removed.isEmpty)
        #expect(delta.changed.isEmpty)
    }

    @Test func diffOnIdenticalSnapshotsIsEmpty() {
        let entries = [entry("a")]
        let delta = InventoryDelta.diff(from: entries, to: entries)
        #expect(delta.isEmpty)
    }

    @Test func diffTreatsDiskChangesAsChangedRows() {
        let before = entry("vm-a")
        let after = VMEntry(name: before.name, source: before.source,
                            running: before.running, state: before.state,
                            diskSize: 40, diskUsage: 35, accessed: before.accessed)
        let delta = InventoryDelta.diff(from: [before], to: [after])
        #expect(delta.added.isEmpty && delta.removed.isEmpty)
        #expect(delta.changed.first?.before.diskSize == 0)
        #expect(delta.changed.first?.after.diskSize == 40)
    }
}
