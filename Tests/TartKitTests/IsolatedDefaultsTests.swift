import Testing
import Foundation
import SharedTestSupport

/// `IsolatedDefaults` and `InMemoryDefaults` must leave no plist file in
/// `~/Library/Preferences`, so the suites stop filling it.
@Suite struct IsolatedDefaultsTests {
    private let fileManager = FileManager.default

    /// Writes a plist file for `suiteName` without `cfprefsd`, standing in
    /// for a file that an earlier write left behind.
    private func writePlist(forSuiteName suiteName: String) throws -> String {
        let path = IsolatedDefaults.plistPath(forSuiteName: suiteName)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["key": "value"], format: .binary, options: 0)
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    @Test func cleanUpDeletesThePlistFile() throws {
        let isolated = IsolatedDefaults(prefix: "IsolatedDefaultsTests")
        _ = isolated.make()
        let suiteName = try #require(isolated.pendingSuiteNames.first)
        let plist = try writePlist(forSuiteName: suiteName)
        #expect(fileManager.fileExists(atPath: plist))

        isolated.cleanUp()

        #expect(!fileManager.fileExists(atPath: plist))
        #expect(isolated.pendingSuiteNames.isEmpty)
    }

    @Test func deinitDeletesThePlistOfEveryDomainItMade() throws {
        var isolated: IsolatedDefaults? = IsolatedDefaults(prefix: "IsolatedDefaultsTests")
        _ = isolated?.make()
        _ = isolated?.make()
        let plists = try (isolated?.pendingSuiteNames ?? []).map(writePlist(forSuiteName:))
        #expect(plists.count == 2)
        #expect(plists.allSatisfy { fileManager.fileExists(atPath: $0) })

        isolated = nil

        #expect(plists.allSatisfy { !fileManager.fileExists(atPath: $0) })
    }

    @Test func writesNeverReachThePreferencesFolder() throws {
        let isolated = IsolatedDefaults(prefix: "IsolatedDefaultsTests")
        let defaults = isolated.make()
        let suiteName = try #require(isolated.pendingSuiteNames.first)
        defaults.set("value", forKey: "string")
        defaults.set(3, forKey: "int")
        _ = defaults.synchronize()
        CFPreferencesAppSynchronize(suiteName as CFString)

        #expect(!fileManager.fileExists(atPath: IsolatedDefaults.plistPath(forSuiteName: suiteName)))
    }

    @Test func inMemoryValuesRoundTripThroughEveryAccessor() {
        let defaults = IsolatedDefaults(prefix: "IsolatedDefaultsTests").make()
        #expect(defaults.object(forKey: "missing") == nil)
        #expect(defaults.integer(forKey: "missing") == 0)
        #expect(!defaults.bool(forKey: "missing"))

        defaults.set("text", forKey: "string")
        defaults.set(7, forKey: "int")
        defaults.set(true, forKey: "bool")
        defaults.set(1.5, forKey: "double")
        defaults.set(Data([1, 2]), forKey: "data")
        defaults.set(["a", "b"], forKey: "strings")
        defaults.set(["k": 1], forKey: "dictionary")

        #expect(defaults.string(forKey: "string") == "text")
        #expect(defaults.integer(forKey: "int") == 7)
        #expect(defaults.object(forKey: "int") as? Int == 7)
        #expect(defaults.bool(forKey: "bool"))
        #expect(defaults.double(forKey: "double") == 1.5)
        #expect(defaults.data(forKey: "data") == Data([1, 2]))
        #expect(defaults.stringArray(forKey: "strings") == ["a", "b"])
        #expect(defaults.dictionary(forKey: "dictionary")?["k"] as? Int == 1)
        #expect(defaults.dictionaryRepresentation().count == 7)

        defaults.removeObject(forKey: "string")
        #expect(defaults.string(forKey: "string") == nil)
    }

    @Test func eachDomainStartsEmpty() {
        let isolated = IsolatedDefaults(prefix: "IsolatedDefaultsTests")
        isolated.make().set("value", forKey: "key")
        #expect(isolated.make().object(forKey: "key") == nil)
    }
}
