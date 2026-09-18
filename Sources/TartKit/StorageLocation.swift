import Foundation

/// Result of validating a candidate storage location at persist-time.
public enum StorageValidation: Equatable, Sendable {
    case valid(path: String)
    case invalid(path: String, reason: String)

    public var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

/// Why the configured storage location is unavailable at runtime.
public enum StorageUnavailableReason: String, Equatable, Sendable {
    /// The path (or its volume) is gone.
    case missing
    /// The path exists but is not writable (e.g. read-only mount).
    case notWritable
}

/// Runtime availability of the configured storage location.
public enum StorageAvailability: Equatable, Sendable {
    case available(path: String)
    case unavailable(path: String, reason: StorageUnavailableReason)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

public enum StorageLocationValidator {
    /// tart's own default home: `~/.tart`.
    public static var defaultPath: String {
        NSString(string: NSHomeDirectory()).appendingPathComponent(".tart")
    }

    /// Persist-time gate: the path must be an existing, writable directory.
    public static func validate(_ path: String) -> StorageValidation {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .invalid(path: path, reason: "Folder does not exist or is not a folder.")
        }
        guard FileManager.default.isWritableFile(atPath: path) else {
            return .invalid(path: path, reason: "Folder is not writable.")
        }
        return .valid(path: path)
    }

    /// Runtime probe of the configured path. The PRD contract for availability
    /// is "mounted/writable", so this checks both existence and writability:
    /// a read-only mount is just as unusable as a missing volume.
    public static func availability(at path: String?) -> StorageAvailability {
        guard let path else { return .unavailable(path: defaultPath, reason: .missing) }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return .unavailable(path: path, reason: .missing)
        }
        guard FileManager.default.isWritableFile(atPath: path) else {
            return .unavailable(path: path, reason: .notWritable)
        }
        return .available(path: path)
    }

    /// Creates the tart home (`~/.tart` by default) if it does not exist yet.
    /// Lives here — next to validation — because it is a filesystem mutation;
    /// the SwiftUI layer contains no business logic. Idempotent.
    @discardableResult
    public static func ensureDefaultExists(at path: String = defaultPath) throws -> String {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }
}
