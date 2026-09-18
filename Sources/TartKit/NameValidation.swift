import Foundation

/// App-level mirror of tart's naming expectations (PRD assumption: "VM names
/// are unique within a storage location (tart enforces this); validation in
/// the app mirrors it for better UX"). tart remains the authority.
public enum VMNameRules {
    /// Letters, digits, dots, dashes, underscores. A leading "-" is rejected
    /// so a name can never be parsed as a CLI flag (finding 11).
    public static let allowedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-") else { return false }
        return name.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
}

/// Syntactic gate for registry image references. Semantic validity is
/// checked by the registry at pull time (PRD: OCI Image validation).
public enum ImageReferenceRules {
    /// Host/repo/tag + digest + `oci://` scheme forms: letters, digits,
    /// `/`, `:`, `@`, `.`, `-`, `_`. A leading "-" is rejected so a
    /// reference can never be parsed as a CLI flag (finding 11).
    public static let allowedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/:@.-_")

    public static func isValid(_ reference: String) -> Bool {
        guard !reference.isEmpty, !reference.hasPrefix("-") else { return false }
        return reference.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
}

/// Name-uniqueness pre-validation (the issue's automated verification,
/// finding 15): syntactic validity plus absence from the current inventory
/// and from in-flight job targets (finding 4).
public enum NameAvailability {
    public static func isAvailable(_ name: String,
                                   inventory: VMInventory?,
                                   activeJobTargets: Set<String>) -> Bool {
        guard VMNameRules.isValid(name) else { return false }
        let existing = (inventory?.localVMs.map(\.name) ?? [])
            + (inventory?.ociImages.map(\.name) ?? [])
        return !existing.contains(name) && !activeJobTargets.contains(name)
    }
}
