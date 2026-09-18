import Testing
import Foundation
@testable import TartKit

@Suite struct VMInventoryTests {
    func entry(_ name: String, source: String = "local") -> VMEntry {
        VMEntry(name: name, source: source, running: false, state: "stopped",
                diskSize: 0, diskUsage: 0, accessed: nil)
    }

    @Test func splitsLocalsAndImagesSortedByName() {
        let inventory = VMInventory(from: [entry("zeta"), entry("alpha"),
                                           entry("img:2", source: "oci"),
                                           entry("img:1", source: "oci")])
        #expect(inventory.localVMs.map(\.name) == ["alpha", "zeta"])
        #expect(inventory.ociImages.map(\.name) == ["img:1", "img:2"])
    }

    @Test func emptyEntriesYieldEmptyInventory() {
        let inventory = VMInventory(from: [])
        #expect(inventory.localVMs.isEmpty)
        #expect(inventory.ociImages.isEmpty)
    }

    @Test func recordsFetchedAt() {
        let inventory = VMInventory(from: [])
        #expect(abs(inventory.fetchedAt.timeIntervalSinceNow) < 5)
    }
}
