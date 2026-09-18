import Testing
import Foundation
@testable import TartKit

@Suite struct InventoryServiceMemoryGatherTests {
    func entry(_ name: String, running: Bool = false, state: String = "stopped") -> VMEntry {
        VMEntry(name: name, source: "local", running: running, state: state,
                diskSize: 40, diskUsage: 20, accessed: nil)
    }

    struct MissingConfig: Error {}

    func configs(_ map: [String: VMConfigInfo]) -> @Sendable (String) async throws -> VMConfigInfo {
        { name in
            guard let config = map[name] else { throw MissingConfig() }
            return config
        }
    }

    @MainActor
    @Test func gatherReturnsNamedRunningAndTargetAllocations() async throws {
        // A large gather timeout isolates the aggregation semantics from
        // the timeout race: under parallel test load the cooperative
        // executor can delay child tasks by seconds, which must not flip
        // the outcome of an instant gather.
        let service = InventoryService(fetch: {
            [entry("vm-a", running: true, state: "running"),
             entry("vm-b", running: true, state: "running"),
             entry("vm-c", running: false)]
        }, memoryGatherTimeout: 60)
        await service.refresh()
        let snapshot = try #require(await service.memoryAllocationSnapshot(
            for: "vm-c",
            getConfig: configs([
                "vm-a": VMConfigInfo(memoryMB: 4096),
                "vm-b": VMConfigInfo(memoryMB: 2048),
                "vm-c": VMConfigInfo(memoryMB: 8192),
            ])))
        // Named fields — running allocations and the target are never
        // conflated into one positional array.
        #expect(snapshot.runningMB == [4096, 2048])
        #expect(snapshot.targetMB == 8192)
    }

    @MainActor
    @Test func missingOrNilConfigsContributeZero() async throws {
        let service = InventoryService(fetch: {
            [entry("vm-a", running: true, state: "running"),
             entry("vm-b", running: true, state: "running"),
             entry("vm-c", running: false)]
        }, memoryGatherTimeout: 60)
        await service.refresh()
        // vm-a: getConfig throws; vm-b: config present but memoryMB nil;
        // vm-c (target): present.
        let getConfig: @Sendable (String) async throws -> VMConfigInfo = { name in
            switch name {
            case "vm-a": throw MissingConfig()
            case "vm-b": return VMConfigInfo(memoryMB: nil)
            default: return VMConfigInfo(memoryMB: 8192)
            }
        }
        let snapshot = try #require(await service.memoryAllocationSnapshot(
            for: "vm-c", getConfig: getConfig))
        #expect(snapshot.runningMB == [0, 0])   // soft degrade, never a gate
        #expect(snapshot.targetMB == 8192)
    }

    @MainActor
    @Test func nilInventoryYieldsNilSnapshot() async {
        let service = InventoryService(fetch: { [] }) // never refreshed
        let snapshot = await service.memoryAllocationSnapshot(
            for: "vm-x", getConfig: configs([:]))
        #expect(snapshot == nil)
    }

    @MainActor
    @Test func suspendedTargetIsTheTargetNotRunning() async throws {
        // A resumed suspended VM IS assessed as the target — the decode
        // normalization reports it as not running, so it is excluded from
        // the running set and its own allocation is the target, exactly
        // like a cold start.
        let service = InventoryService(fetch: {
            [entry("vm-a", running: true, state: "running"),
             entry("vm-b", running: false, state: "suspended")]
        }, memoryGatherTimeout: 60)
        await service.refresh()
        let snapshot = try #require(await service.memoryAllocationSnapshot(
            for: "vm-b",
            getConfig: configs([
                "vm-a": VMConfigInfo(memoryMB: 8192),
                "vm-b": VMConfigInfo(memoryMB: 8192),
            ])))
        #expect(snapshot.runningMB == [8192])
        #expect(snapshot.targetMB == 8192)
    }

    @MainActor
    @Test func gatherTimeoutReturnsNilWithoutWaitingForTheGather() async {
        // The whole gather is bounded by the named timeout; a slow config
        // fetch degrades to nil (no warning, run proceeds) instead of
        // blocking the Run path.
        let service = InventoryService(fetch: {
            [entry("vm-a", running: true, state: "running"), entry("vm-c")]
        }, memoryGatherTimeout: 0.2)
        await service.refresh()
        actor SlowFetchFlag {
            var completed = false
            func markCompleted() { completed = true }
        }
        let flag = SlowFetchFlag()
        let slowConfig: @Sendable (String) async throws -> VMConfigInfo = { _ in
            try await Task.sleep(for: .seconds(30))
            await flag.markCompleted()
            return VMConfigInfo(memoryMB: 1024)
        }
        let started = Date()
        let snapshot = await service.memoryAllocationSnapshot(
            for: "vm-c", getConfig: slowConfig)
        #expect(snapshot == nil)
        // Deterministic proof the deadline interrupted the slow fetch: the
        // 30 s sleep never ran to completion. An unenforced gather would
        // have returned the snapshot only after the fetch finished.
        #expect(await flag.completed == false)
        // Loose wall-clock sanity (an unenforced gather waits out two 30 s
        // fetches): tolerates cooperative-executor jitter under parallel
        // test load while still failing loudly if the cancellation is
        // ever dropped.
        #expect(Date().timeIntervalSince(started) < 20)
    }
}
