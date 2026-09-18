import Foundation

/// A small lock-protected value used by synchronous callbacks in tests.
/// The callbacks may execute on a detached worker, so test observations must
/// not mutate a captured local variable directly.
final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    func withValue(_ update: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        update(&storage)
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
