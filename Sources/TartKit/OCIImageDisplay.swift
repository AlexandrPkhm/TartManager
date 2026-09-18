/// Display components of an OCI reference. The original is retained unchanged for cloning.
public struct OCIImageDisplay: Equatable, Sendable {
    public let reference: String
    public let repository: String
    public let name: String
    public let version: String?
    public let isDigest: Bool

    public init(reference: String) {
        self.reference = reference
        if let separator = reference.firstIndex(of: "@") {
            repository = String(reference[..<separator])
            version = String(reference[reference.index(after: separator)...])
            isDigest = true
        } else if let separator = reference.lastIndex(of: ":"),
                  !reference[separator...].contains("/") {
            repository = String(reference[..<separator])
            version = String(reference[reference.index(after: separator)...])
            isDigest = false
        } else {
            repository = reference
            version = nil
            isDigest = false
        }
        name = String(repository.split(separator: "/").last ?? Substring(repository))
    }
}
