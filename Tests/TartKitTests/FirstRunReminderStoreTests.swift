import Testing
import Foundation
import SharedTestSupport
@testable import TartKit

@Suite struct FirstRunReminderStoreTests {
    /// Removes this test's `UserDefaults` domain and its plist file.
    private let isolatedDefaults = IsolatedDefaults(prefix: "FirstRunReminderStoreTests")

    func makeStore() -> (store: FirstRunReminderStore, defaults: UserDefaults) {
        let defaults = isolatedDefaults.make()
        return (FirstRunReminderStore(defaults: defaults), defaults)
    }

    @Test func flagContainsUnflagRoundTrip() {
        let (store, _) = makeStore()
        #expect(!store.contains("vm-a"))
        store.flag("vm-a")
        #expect(store.contains("vm-a"))
        #expect(!store.contains("other"))
        store.unflag("vm-a")
        #expect(!store.contains("vm-a"))
    }

    @Test func flagsPersistAcrossStoreInstances() {
        let (store, defaults) = makeStore()
        store.flag("vm-a")
        let revived = FirstRunReminderStore(defaults: defaults)
        #expect(revived.contains("vm-a")) // survives app relaunch
    }

    @Test func pruneKeepsOnlyLiveNames() {
        let (store, _) = makeStore()
        store.flag("vm-a")
        store.flag("vm-b")
        store.prune(keeping: Set(["vm-b"])) // vm-a was deleted
        #expect(!store.contains("vm-a"))
        #expect(store.contains("vm-b"))
    }

    @Test func flagIsIdempotent() {
        let (store, _) = makeStore()
        store.flag("vm-a")
        store.flag("vm-a")
        store.unflag("vm-a")
        #expect(!store.contains("vm-a")) // no duplicate key lingers
    }
}
