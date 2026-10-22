import Foundation

/// The result of validating a user-chosen tart executable path.
public enum TartCustomPathValidation: Equatable, Sendable {
    case valid(String)
    case invalid(String, Reason)

    /// Why a custom path cannot be used.
    public enum Reason: String, Sendable {
        case notAbsolute
        case missing
        case notRegularFile
        case notExecutable
    }
}

/// Validates a custom tart path before it is stored or run.
///
/// A valid path is absolute, exists, resolves (through symlinks) to a regular
/// file, and is executable. A Homebrew wrapper script passes. The valid result
/// keeps the original, unresolved path so the user sees what they chose.
public enum TartCustomPathValidator {
    public static func validate(_ path: String) -> TartCustomPathValidation {
        guard path.hasPrefix("/") else { return .invalid(path, .notAbsolute) }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory) else {
            return .invalid(path, .missing)
        }
        guard !isDirectory.boolValue,
              (try? FileManager.default.attributesOfItem(atPath: resolved)[.type]
                  as? FileAttributeType) == .typeRegular else {
            return .invalid(path, .notRegularFile)
        }
        guard FileManager.default.isExecutableFile(atPath: resolved) else {
            return .invalid(path, .notExecutable)
        }
        return .valid(path)
    }
}
