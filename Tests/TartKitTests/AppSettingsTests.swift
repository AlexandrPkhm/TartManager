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

    @Test func appearanceDefaultsToSystemAndPersistsEveryChoice() {
        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.appearance == .system)
        for appearance in [AppAppearance.light, .dark, .system] {
            settings.appearance = appearance
            #expect(AppSettings(defaults: defaults).appearance == appearance)
        }
    }

    @Test func unknownAppearanceFallsBackToSystem() {
        let defaults = makeIsolatedDefaults()
        defaults.set("unknown", forKey: AppSettings.appearanceKey)
        #expect(AppSettings(defaults: defaults).appearance == .system)
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

    @Test func cachePrunePolicyDefaultsAndRoundTripsIncludingManual() {
        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.cachePrunePolicy == .fourteenDays)
        for policy in CachePrunePolicy.allCases {
            settings.cachePrunePolicy = policy
            #expect(AppSettings(defaults: defaults).cachePrunePolicy == policy)
        }
    }

    @Test func cachePrunePolicyPreservesLegacyChoicesAndDefaultsUnknown() {
        let defaults = makeIsolatedDefaults()
        for (raw, expected) in [(7, CachePrunePolicy.sevenDays), (14, .fourteenDays),
                                (30, .thirtyDays), (0, .manual), (5, .fourteenDays),
                                (-1, .fourteenDays)] {
            defaults.set(raw, forKey: AppSettings.pruneRetentionDaysKey)
            #expect(AppSettings(defaults: defaults).cachePrunePolicy == expected)
        }
    }

    @Test func automaticPruneAttemptsPersistSeparatelyForEachStorage() {
        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        let date = Date(timeIntervalSince1970: 123_456)
        #expect(settings.lastAutomaticPruneAttempt(forStoragePath: "/tmp/a") == nil)
        settings.recordAutomaticPruneAttempt(at: date, forStoragePath: "/tmp/a")
        let restored = AppSettings(defaults: defaults)
        #expect(restored.lastAutomaticPruneAttempt(forStoragePath: "/tmp/a") == date)
        #expect(restored.lastAutomaticPruneAttempt(forStoragePath: "/tmp/b") == nil)
    }

    @Test func malformedCachePolicyDoesNotEnableManualMode() {
        let defaults = makeIsolatedDefaults()
        defaults.set("unsupported", forKey: AppSettings.pruneRetentionDaysKey)
        #expect(AppSettings(defaults: defaults).cachePrunePolicy == .fourteenDays)
    }

    @Test func displayRefitPreferenceRoundTripsPerVM() {
        let defaults = makeIsolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.displayRefitPreference(for: "vm-a") == nil)

        settings.setDisplayRefitPreference(true, for: "vm-a")
        settings.setDisplayRefitPreference(false, for: "vm-b")

        let restored = AppSettings(defaults: defaults)
        #expect(restored.displayRefitPreference(for: "vm-a") == true)
        #expect(restored.displayRefitPreference(for: "vm-b") == false)
        #expect(restored.displayRefitPreference(for: "vm-c") == nil)
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
