import Testing
import Foundation
@testable import TartKit

@Suite struct InventoryServiceTests {
    func entry(_ name: String, source: String = "local",
               running: Bool = false, state: String = "stopped") -> VMEntry {
        VMEntry(name: name, source: source, running: running, state: state,
                diskSize: 0, diskUsage: 0, accessed: nil)
    }

    @MainActor
    @Test func refreshPublishesFetchedInventory() async {
        let service = InventoryService(fetch: { [entry("vm-a")] })
        #expect(service.inventory == nil)
        #expect(service.lastDelta == nil)
        await service.refresh()
        #expect(service.inventory?.localVMs.map(\.name) == ["vm-a"])
        #expect(service.lastDelta == nil) // first fetch has no predecessor
    }

    @MainActor
    @Test func successivePollsDiffAddedRemovedChanged() async {
        let service = InventoryService(fetch: {
            [entry("vm-a"), entry("img:1", source: "oci")]
        })
        await service.refresh()
        service.updateFetch {
            [entry("vm-a", running: true, state: "running"), entry("vm-b")]
        }
        await service.refresh()
        let delta = service.lastDelta
        #expect(delta?.added.map(\.name) == ["vm-b"])
        #expect(delta?.removed.map(\.name) == ["img:1"])
        #expect(delta?.changed.map(\.after.name) == ["vm-a"])
        #expect(delta?.changed.first?.before.state == "stopped")
        #expect(delta?.changed.first?.after.state == "running")
    }

    @MainActor
    @Test func emptyOutputReplacesInventoryAndReportsRemovals() async {
        let service = InventoryService(fetch: { [entry("vm-a"), entry("vm-b")] })
        await service.refresh()
        service.updateFetch { [] }
        await service.refresh()
        #expect(service.inventory?.localVMs.isEmpty == true)
        #expect(service.inventory?.ociImages.isEmpty == true)
        #expect(service.lastDelta?.added.isEmpty == true)
        #expect(service.lastDelta?.removed.map(\.name) == ["vm-a", "vm-b"])
    }

    @MainActor
    @Test func refreshKeepsLastInventoryOnFailureAndReportsIt() async {
        let service = InventoryService(fetch: { [entry("vm-a")] })
        var reported: [Error] = []
        service.onFetchFailure = { reported.append($0) }
        await service.refresh()
        let before = service.inventory
        service.updateFetch { throw InventoryFetchError.unavailable }
        await service.refresh()
        #expect(service.inventory == before)          // did not nuke on failure
        #expect(service.lastDelta == nil)             // no bogus delta on failure
        #expect(reported.count == 1)
        #expect(reported.first as? InventoryFetchError != nil)
    }

    @MainActor
    @Test func overlappingRefreshesPerformOnlyOneFetch() async {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            func increment() { lock.lock(); count += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        }
        let counter = Counter()
        let service = InventoryService(fetch: {
            counter.increment()
            Thread.sleep(forTimeInterval: 0.2)
            return []
        }, pollInterval: 3600)
        let first = Task { await service.refresh() }
        let second = Task { await service.refresh() }
        await first.value
        await second.value
        #expect(counter.value == 1) // in-flight guard dropped the overlap
    }

    @MainActor
    @Test func stopPollingCancelsLoop() async {
        let service = InventoryService(fetch: { [] }, pollInterval: 0.01)
        service.startPolling()
        service.stopPolling()
        // No crash, no hang; loop cancelled promptly.
        try? await Task.sleep(for: .seconds(0.05))
    }
}

extension InventoryServiceTests {
    @MainActor
    @Test func refreshIfStaleSkipsWhenPollJustRan() async {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            func increment() { lock.lock(); count += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        }
        let counter = Counter()
        let service = InventoryService(fetch: {
            counter.increment()
            return []
        }, pollInterval: 3600)
        await service.refresh()
        #expect(service.lastFetchedAt != nil)
        // A post-run refresh right after a completed poll is coalesced away.
        await service.refreshIfStale(olderThan: 0.2)
        #expect(counter.value == 1)
        // Once the interval has passed, the refresh runs again.
        try? await Task.sleep(for: .milliseconds(250))
        await service.refreshIfStale(olderThan: 0.2)
        #expect(counter.value == 2)
    }

    @MainActor
    @Test func refreshIfStaleProceedsAfterFailedFetch() async {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            func increment() { lock.lock(); count += 1; lock.unlock() }
            var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        }
        let counter = Counter()
        let service = InventoryService(fetch: {
            counter.increment()
            throw InventoryFetchError.unavailable
        }, pollInterval: 3600)
        await service.refresh()
        #expect(service.lastFetchedAt == nil) // failures never mark a fetch
        await service.refreshIfStale(olderThan: 0.2)
        #expect(counter.value == 2) // a failed poll must not block the next attempt
    }

    @MainActor
    @Test func pausedServiceSkipsFetches() async {
        var calls = 0
        let service = InventoryService(fetch: { calls += 1; return [] })
        service.pause()
        #expect(service.isPaused)
        await service.refresh()
        await service.refreshIfStale()
        #expect(calls == 0)
        #expect(service.inventory == nil)
    }

    @MainActor
    @Test func resumeAllowsFetchesAgain() async {
        var calls = 0
        let service = InventoryService(fetch: { calls += 1; return [] })
        service.pause()
        #expect(service.resume())
        #expect(!service.isPaused)
        await service.refresh()
        #expect(calls == 1)
        #expect(service.inventory != nil)
    }

    @MainActor
    @Test func resumeWithoutPauseReportsNoChange() {
        let service = InventoryService(fetch: { [] })
        #expect(service.resume() == false)
        #expect(!service.isPaused)
    }
}
