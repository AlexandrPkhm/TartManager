import Foundation

/// Hands out isolated `UserDefaults` domains for one test and removes them
/// when the test ends.
///
/// Store one instance as a property of the suite. Swift Testing creates a
/// new suite instance for each test and releases it when the test ends, so
/// `deinit` removes every domain the test made.
///
/// Why values stay in memory: once a process writes to a domain, or calls
/// `removePersistentDomain(forName:)` on one that has a file, `cfprefsd`
/// keeps an empty `~/Library/Preferences/<suite>.plist` for it. Deleting
/// the file then does not help: `cfprefsd` writes it again a few seconds
/// later. Before this helper the suites left thousands of these files.
/// So `make()` returns `InMemoryDefaults`, which never sends a value to
/// `cfprefsd`, and `cleanUp()` only deletes a plist file that is there,
/// without a `cfprefsd` call that would bring it back.
///
/// Invariant: `lock` guards `suiteNames`.
public final class IsolatedDefaults: @unchecked Sendable {
    private let prefix: String
    private let lock = NSLock()
    private var suiteNames: [String] = []

    /// - Parameter prefix: The start of each suite name, usually the suite
    ///   type's name, so a leaked file shows which suite made it.
    public init(prefix: String) {
        self.prefix = prefix
    }

    deinit {
        cleanUp()
    }

    /// Creates a new empty domain and records it for cleanup.
    public func make() -> InMemoryDefaults {
        let suiteName = "\(prefix)-\(UUID().uuidString)"
        lock.lock()
        suiteNames.append(suiteName)
        lock.unlock()
        return InMemoryDefaults(suiteName: suiteName)!
    }

    /// The names of the domains that cleanup will remove.
    public var pendingSuiteNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return suiteNames
    }

    /// Removes every domain this instance made. `deinit` calls it; calling
    /// it again is harmless.
    public func cleanUp() {
        lock.lock()
        let names = suiteNames
        suiteNames.removeAll()
        lock.unlock()
        names.forEach(Self.remove(suiteName:))
    }

    /// The file in which `cfprefsd` stores `suiteName` for the current user.
    public static func plistPath(forSuiteName suiteName: String) -> String {
        NSHomeDirectory() + "/Library/Preferences/\(suiteName).plist"
    }

    /// Deletes the domain's plist file if it exists.
    ///
    /// It deliberately does not call `removePersistentDomain(forName:)`:
    /// that call makes `cfprefsd` write the empty file again later.
    public static func remove(suiteName: String) {
        let path = plistPath(forSuiteName: suiteName)
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }
}
