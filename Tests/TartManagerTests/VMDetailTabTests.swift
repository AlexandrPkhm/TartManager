import Testing
@testable import TartKit
@testable import TartManager

@Suite struct VMDetailTabTests {
    @Test func localVMOffersManagementTabs() {
        let localVM = VMEntry(name: "macos-dev",
                              source: "local",
                              running: false,
                              state: "stopped",
                              diskSize: 50,
                              diskUsage: 12,
                              accessed: nil)

        #expect(VMDetailTab.available(for: localVM) == [.overview, .snapshots, .sharedFolders])
    }

    @Test func OCIImageKeepsOnlyTheOverviewTab() {
        let image = VMEntry(name: "ghcr.io/example/macos:latest",
                            source: "ghcr.io/example/macos:latest",
                            running: false,
                            state: "",
                            diskSize: 0,
                            diskUsage: 0,
                            accessed: nil)

        #expect(VMDetailTab.available(for: image) == [.overview])
    }
}
