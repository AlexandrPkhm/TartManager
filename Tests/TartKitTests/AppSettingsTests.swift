import Testing
import Foundation
@testable import TartKit

@Suite struct AppSettingsTests {
    func makeIsolatedDefaults() -> UserDefaults {
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func roundTripsStoragePath() {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        #expect(settings.storagePath == nil)
        settings.storagePath = "/tmp/somewhere"
        #expect(settings.storagePath == "/tmp/somewhere")
    }

    @Test func clearingStoragePathRemovesIt() {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.storagePath = "/tmp/somewhere"
        settings.storagePath = nil
        #expect(settings.storagePath == nil)
    }

    @Test func persistenceSurvivesNewInstance() {
        let defaults = makeIsolatedDefaults()
        AppSettings(defaults: defaults).storagePath = "/tmp/kept"
        #expect(AppSettings(defaults: defaults).storagePath == "/tmp/kept")
    }

    @Test func sshUserDefaultsToAdminAndRoundTrips() {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        #expect(settings.sshUser == "admin")
        settings.sshUser = "circleci"
        #expect(settings.sshUser == "circleci")
    }

    @Test func sshUserTrimsAndFallsBack() {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.sshUser = "  spaced  "
        #expect(settings.sshUser == "spaced")
        settings.sshUser = "   "
        #expect(settings.sshUser == "admin")
    }

    @Test func snapshotsFolderRoundTripsAndDefaultsToNil() {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        #expect(settings.snapshotsFolder == nil)
        settings.snapshotsFolder = "/Volumes/SSD/Snapshots"
        #expect(settings.snapshotsFolder == "/Volumes/SSD/Snapshots")
        settings.snapshotsFolder = nil
        #expect(settings.snapshotsFolder == nil)
    }

    @Test func pruneRetentionDaysDefaultsAndRoundTrips() {
        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.pruneRetentionDays == 14) // default when unset
        settings.pruneRetentionDays = 7
        #expect(settings.pruneRetentionDays == 7)
        #expect(AppSettings(defaults: defaults).pruneRetentionDays == 7) // persisted
        settings.pruneRetentionDays = 30
        #expect(settings.pruneRetentionDays == 30)
    }

    @Test func pruneRetentionDaysRejectsUnsupportedValues() {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.pruneRetentionDays = 5
        #expect(settings.pruneRetentionDays == 14) // invalid value ignored
        settings.pruneRetentionDays = 0
        #expect(settings.pruneRetentionDays == 14)
    }

    func share(_ name: String) throws -> VMFolderShare {
        try VMFolderShare.make(name: name, hostPath: "/tmp/\(name)",
                               readOnly: false, customTag: nil)
    }

    @Test func unknownVMHasNoSharedFolders() {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        #expect(settings.sharedFolders(for: "vm-a").isEmpty)
    }

    @Test func sharedFoldersRoundTripPerVM() throws {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        let list = [try share("build"), try share("sources")]
        settings.setSharedFolders(list, for: "vm-a")
        #expect(settings.sharedFolders(for: "vm-a") == list)
    }

    @Test func sharedFolderListsAreIsolatedPerVMAndRemovable() throws {
        let settings = AppSettings(defaults: makeIsolatedDefaults())
        settings.setSharedFolders([try share("one")], for: "vm-a")
        settings.setSharedFolders([try share("two"), try share("three")], for: "vm-b")
        #expect(settings.sharedFolders(for: "vm-a").count == 1)
        #expect(settings.sharedFolders(for: "vm-b").count == 2)
        settings.setSharedFolders([], for: "vm-a")
        #expect(settings.sharedFolders(for: "vm-a").isEmpty)
        #expect(settings.sharedFolders(for: "vm-b").count == 2)
    }
}
