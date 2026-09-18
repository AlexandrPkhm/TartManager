import Testing
import Foundation
@testable import TartKit

@Suite struct VMDetailsResolverTests {
    func entry(_ name: String, source: String = "local", running: Bool = false) -> VMEntry {
        VMEntry(name: name, source: source, running: running,
                state: running ? "running" : "stopped",
                diskSize: 40, diskUsage: 27.5, accessed: nil)
    }

    @Test func planSkipsEveryCallForOCISelections() {
        // OCI rows have no config.json — `tart get` cannot succeed — and no
        // guest to IP-check.
        let plan = VMDetailsResolver.plan(
            for: entry("img:1", source: "OCI", running: true), configIsCached: false)
        #expect(!plan.fetchConfig)
        #expect(!plan.fetchIP)
    }

    @Test func planFetchesConfigOnceThenCaches() {
        let stopped = entry("vm-a", running: false)
        #expect(VMDetailsResolver.plan(for: stopped, configIsCached: false).fetchConfig)
        // Config is static in this slice; a cached selection re-fetches nothing.
        let cachedPlan = VMDetailsResolver.plan(for: stopped, configIsCached: true)
        #expect(!cachedPlan.fetchConfig)
        #expect(!cachedPlan.fetchIP)
    }

    @Test func planFetchesIPOnlyForRunningLocals() {
        let running = entry("vm-a", running: true)
        let stopped = entry("vm-a", running: false)
        #expect(VMDetailsResolver.plan(for: running, configIsCached: true).fetchIP)
        #expect(!VMDetailsResolver.plan(for: stopped, configIsCached: true).fetchIP)
    }

    @Test func planFetchesConfigAndIPForRunningUncachedLocal() {
        let plan = VMDetailsResolver.plan(for: entry("vm-a", running: true),
                                          configIsCached: false)
        #expect(plan.fetchConfig)
        #expect(plan.fetchIP)
    }

    @Test func assembleKeepsIPOnlyForRunningLocals() {
        let running = entry("vm-a", running: true)
        #expect(VMDetailsResolver.assemble(
            entry: running, config: nil, ip: "192.168.64.2", fetchedAt: Date()).ip
            == "192.168.64.2")
        // Placeholder-when-stopped: an IP fetched for a since-stopped VM
        // must never be published.
        let stopped = entry("vm-a", running: false)
        #expect(VMDetailsResolver.assemble(
            entry: stopped, config: nil, ip: "192.168.64.2", fetchedAt: Date()).ip == nil)
    }

    @Test func assembleDropsIPAndPassesNilConfigForOCISelections() {
        let oci = entry("img:1", source: "OCI", running: true)
        let details = VMDetailsResolver.assemble(
            entry: oci, config: nil, ip: "192.168.64.2", fetchedAt: Date())
        #expect(details.ip == nil)
        #expect(details.config == nil)
    }
}
