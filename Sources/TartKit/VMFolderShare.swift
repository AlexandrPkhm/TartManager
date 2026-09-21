import Foundation

public enum VMFolderShareError: Error, Equatable {
    case invalidName(String)
    case invalidHostPath(String)
    case invalidTag(String)
}

/// One host folder shared into a VM — tart's `--dir` value, persisted per VM.
///
/// One validation contract, enforced at both entry points:
/// - `make` REJECTS (throws) empty names, `:`/`,` in the name or custom tag,
///   and `:`/`,` in the host path — those characters would make tart's
///   `--dir` parse ambiguous, so they are never silently mangled away.
/// - Mount names preserve internal spaces while custom tags map spaces to
///   `-`; everything else outside their share charset is stripped.
/// - The edit path (`set(name:)` / `set(customTag:)`) applies the same
///   sanitization, and `isValidForPersistence` lets `persist()` re-verify
///   before anything is saved.
public struct VMFolderShare: Equatable, Codable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var hostPath: String
    public var readOnly: Bool
    public var customTag: String?

    /// Unvalidated memberwise initializer — exists for Codable decoding and
    /// tests only; production code creates shares via `make` and edits them
    /// via `set(name:)`/`set(customTag:)`, both of which enforce the
    /// contract above.
    public init(id: UUID = UUID(), name: String, hostPath: String,
                readOnly: Bool, customTag: String?) {
        self.id = id
        self.name = name
        self.hostPath = hostPath
        self.readOnly = readOnly
        self.customTag = customTag
    }

    /// Creates a validated share. Throws `VMFolderShareError` on any value
    /// that would make the `--dir` argument ambiguous: an empty name, `:`/`,`
    /// in the name, tag, or host path. `makeDefault` derives the name from
    /// the folder.
    public static func make(name: String, hostPath: String,
                            readOnly: Bool, customTag: String?) throws -> VMFolderShare {
        guard !name.contains(":"), !name.contains(",") else {
            throw VMFolderShareError.invalidName(name)
        }
        guard !hostPath.isEmpty, !hostPath.contains(":"), !hostPath.contains(",") else {
            throw VMFolderShareError.invalidHostPath(hostPath)
        }
        let sanitizedTag: String?
        if let customTag {
            guard !customTag.contains(":"), !customTag.contains(",") else {
                throw VMFolderShareError.invalidTag(customTag)
            }
            let tag = Self.sanitizeTag(customTag)
            guard !tag.isEmpty else { throw VMFolderShareError.invalidTag(customTag) }
            sanitizedTag = tag
        } else {
            sanitizedTag = nil
        }
        let sanitizedName = Self.sanitizeName(name)
        guard !sanitizedName.isEmpty else { throw VMFolderShareError.invalidName(name) }
        return VMFolderShare(name: sanitizedName, hostPath: hostPath,
                             readOnly: readOnly, customTag: sanitizedTag)
    }

    /// Share named after the folder (sanitized), read-write, default automount tag.
    public static func makeDefault(hostPath: String) throws -> VMFolderShare {
        let folderName = (hostPath as NSString).lastPathComponent
        return try make(name: folderName, hostPath: hostPath,
                        readOnly: false, customTag: nil)
    }

    /// tart's `--dir` value: `[name:]path[:options]`, options comma-joined.
    public var dirArgument: String {
        var options: [String] = []
        if readOnly { options.append("ro") }
        if let customTag { options.append("tag=\(customTag)") }
        let renderedOptions = options.isEmpty ? "" : ":" + options.joined(separator: ",")
        return "\(name):\(hostPath)\(renderedOptions)"
    }

    // MARK: Edit path — the same charset rules `make` enforces (finding 5)

    /// Mutates the name through the share charset: `:` and `,` are stripped
    /// (never stored), outer whitespace is trimmed, internal spaces are
    /// preserved, and everything else outside `[A-Za-z0-9 _-]` is dropped.
    /// Non-throwing so it can back a live
    /// TextField binding; `isValidForPersistence`/`persist()` is the second
    /// gate before anything is saved.
    public mutating func set(name rawName: String) {
        name = Self.cleanEditableName(rawName)
    }

    /// Empty (trimmed) input clears the tag to nil; otherwise spaces map to
    /// hyphens and the tag charset rules apply.
    public mutating func set(customTag rawTag: String) {
        let trimmed = rawTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { customTag = nil; return }
        customTag = Self.cleanEditableTag(trimmed)
    }

    /// True when the stored values render an unambiguous `--dir` argument —
    /// the predicate `persist()` enforces before saving (defense in depth
    /// against any future path that bypasses the bindings).
    public var isValidForPersistence: Bool {
        guard !name.isEmpty,
              !name.contains(":"), !name.contains(","),
              name == Self.sanitizeName(name) else { return false }
        guard !hostPath.isEmpty,
              !hostPath.contains(":"), !hostPath.contains(",") else { return false }
        if let customTag {
            return !customTag.contains(":") && !customTag.contains(",")
                && customTag == Self.sanitizeTag(customTag)
        }
        return true
    }

    /// Restricts a native Tart mount name to a conservative share charset,
    /// preserving internal spaces and trimming the outer whitespace.
    private static func sanitizeName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = trimmed.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " " || scalar == "-" || scalar == "_"
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Restricts a manual virtiofs tag to `[A-Za-z0-9_-]`, mapping spaces to
    /// hyphens before removing other unsupported characters.
    private static func sanitizeTag(_ raw: String) -> String {
        let spacesMapped = raw.replacingOccurrences(of: " ", with: "-")
        let scalars = spacesMapped.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_"
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Edit-path application of the mount-name contract: strip Tart's
    /// delimiter characters, then preserve allowed internal spaces.
    private static func cleanEditableName(_ raw: String) -> String {
        sanitizeName(raw
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ",", with: ""))
    }

    /// Edit-path application of the custom-tag contract: strip Tart's
    /// delimiter characters, then map spaces to hyphens.
    private static func cleanEditableTag(_ raw: String) -> String {
        sanitizeTag(raw
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ",", with: ""))
    }
}
