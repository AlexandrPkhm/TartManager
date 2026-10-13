/// Cache retention policy. Manual preserves caches until explicit cleanup;
/// day-based policies prune entries older than their retention age.
public enum CachePrunePolicy: Int, CaseIterable, Sendable {
    case manual = 0
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    /// Nil means explicit cleanup removes caches of every age.
    public var retentionDays: Int? { self == .manual ? nil : rawValue }

    /// User-facing picker label.
    public var label: String { self == .manual ? "Manual" : "\(rawValue) days" }
}
