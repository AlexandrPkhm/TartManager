import Testing
import Foundation
@testable import TartKit

@Suite struct FirstRunReminderStoreTests {
    func makeStore() -> (store: FirstRunReminderStore, suite: String) {
        let suite = "tartmanager-tests-\(UUID().uuidString)"
        return (FirstRunReminderStore(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    @Test func flagContainsUnflagRoundTrip() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(!store.contains("vm-a"))
        store.flag("vm-a")
        #expect(store.contains("vm-a"))
        #expect(!store.contains("other"))
        store.unflag("vm-a")
        #expect(!store.contains("vm-a"))
    }

    @Test func flagsPersistAcrossStoreInstances() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        store.flag("vm-a")
        let revived = FirstRunReminderStore(defaults: UserDefaults(suiteName: suite)!)
        #expect(revived.contains("vm-a")) // survives app relaunch
    }

    @Test func pruneKeepsOnlyLiveNames() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        store.flag("vm-a")
        store.flag("vm-b")
        store.prune(keeping: Set(["vm-b"])) // vm-a was deleted
        #expect(!store.contains("vm-a"))
        #expect(store.contains("vm-b"))
    }

    @Test func flagIsIdempotent() {
        let (store, suite) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        store.flag("vm-a")
        store.flag("vm-a")
        store.unflag("vm-a")
        #expect(!store.contains("vm-a")) // no duplicate key lingers
    }
}
