import Foundation
import os

/// One pullable image of the default registry.
public struct DefaultRegistryImage: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let label: String
    public let reference: String

    public var id: String { reference }

    public init(label: String, reference: String) {
        self.label = label
        self.reference = reference
    }
}

/// The image list of the default registry, `ghcr.io/cirruslabs`. GHCR does
/// not let an anonymous client list an organization's images, so the list
/// is a JSON file in this repository (`Catalog/default-registry-images.json`).
/// A downloaded list can name only images of the default registry, so a bad
/// file cannot send the app to another registry.
public enum DefaultRegistryCatalog {
    public static let schemaVersion = 1
    public static let referencePrefix = "ghcr.io/cirruslabs/"

    public enum DecodeError: Error, Equatable, Sendable {
        case unsupportedSchema(Int)
        case noUsableImages
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let images: [DefaultRegistryImage]
    }

    /// The list for a first launch without a network. It can be older than
    /// the repository file: the next successful download replaces it.
    public static let builtIn: [DefaultRegistryImage] = {
        let families = [("Golden Gate", "golden-gate"), ("Tahoe", "tahoe"), ("Sequoia", "sequoia"),
                        ("Sonoma", "sonoma"), ("Ventura", "ventura"), ("Monterey", "monterey")]
        let macOS = families.flatMap { name, slug in
            ["base", "vanilla", "xcode"].map { flavor in
                DefaultRegistryImage(label: "macOS \(name) · \(flavor)",
                                     reference: "\(referencePrefix)macos-\(slug)-\(flavor):latest")
            }
        }
        let linux = [("Ubuntu", "ubuntu"), ("Debian", "debian"), ("Fedora", "fedora")].map { name, slug in
            DefaultRegistryImage(label: name, reference: "\(referencePrefix)\(slug):latest")
        }
        return macOS + linux
    }()

    /// True when the entry has a label and a valid reference in the default
    /// registry.
    public static func isAllowed(_ image: DefaultRegistryImage) -> Bool {
        !image.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && image.reference.hasPrefix(referencePrefix)
            && !image.reference.contains("..")
            && ImageReferenceRules.isValid(image.reference)
    }

    /// Decodes a catalog file and drops the entries that are not allowed.
    /// Throws for an unknown schema or when no entry remains, so a bad file
    /// never replaces a good list.
    public static func decode(_ data: Data) throws -> [DefaultRegistryImage] {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == schemaVersion else {
            throw DecodeError.unsupportedSchema(document.schemaVersion)
        }
        let images = document.images.filter(isAllowed)
        if images.count != document.images.count {
            let dropped = document.images.count - images.count
            Logger.registries.error("default registry catalog: dropped \(dropped, privacy: .public) invalid entries")
        }
        guard !images.isEmpty else { throw DecodeError.noUsableImages }
        return images
    }
}
