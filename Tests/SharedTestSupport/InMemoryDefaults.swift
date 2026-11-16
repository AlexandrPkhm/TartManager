import Foundation

/// A `UserDefaults` that keeps its values in memory and never writes them
/// to `cfprefsd`, so a test leaves no plist file behind.
///
/// It overrides every accessor that Tart Manager and its tests call. It
/// does not read the global or registration domains: a key that was never
/// set reads as `nil`, as in a new isolated suite.
///
/// Invariant: `lock` guards `values`.
public final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    public override init?(suiteName: String?) {
        super.init(suiteName: suiteName)
    }

    // MARK: Storage

    public override func object(forKey defaultName: String) -> Any? {
        lock.lock()
        defer { lock.unlock() }
        return values[defaultName]
    }

    public override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock()
        defer { lock.unlock() }
        values[defaultName] = value
    }

    public override func removeObject(forKey defaultName: String) {
        set(nil, forKey: defaultName)
    }

    public override func dictionaryRepresentation() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    public override func synchronize() -> Bool {
        true
    }

    // MARK: Typed setters

    public override func set(_ value: Int, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public override func set(_ value: Bool, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public override func set(_ value: Double, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public override func set(_ value: Float, forKey defaultName: String) {
        set(value as Any, forKey: defaultName)
    }

    public override func set(_ url: URL?, forKey defaultName: String) {
        set(url as Any?, forKey: defaultName)
    }

    // MARK: Typed getters

    public override func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    public override func data(forKey defaultName: String) -> Data? {
        object(forKey: defaultName) as? Data
    }

    public override func array(forKey defaultName: String) -> [Any]? {
        object(forKey: defaultName) as? [Any]
    }

    public override func stringArray(forKey defaultName: String) -> [String]? {
        object(forKey: defaultName) as? [String]
    }

    public override func dictionary(forKey defaultName: String) -> [String: Any]? {
        object(forKey: defaultName) as? [String: Any]
    }

    public override func integer(forKey defaultName: String) -> Int {
        (object(forKey: defaultName) as? NSNumber)?.intValue ?? 0
    }

    public override func bool(forKey defaultName: String) -> Bool {
        (object(forKey: defaultName) as? NSNumber)?.boolValue ?? false
    }

    public override func double(forKey defaultName: String) -> Double {
        (object(forKey: defaultName) as? NSNumber)?.doubleValue ?? 0
    }

    public override func float(forKey defaultName: String) -> Float {
        (object(forKey: defaultName) as? NSNumber)?.floatValue ?? 0
    }

    public override func url(forKey defaultName: String) -> URL? {
        object(forKey: defaultName) as? URL
    }
}
