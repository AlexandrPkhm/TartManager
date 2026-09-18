import Foundation

/// Snapshot of `tart list` at a point in time, split by runnability.
public struct VMInventory: Equatable, Sendable {
    public let localVMs: [VMEntry]
    public let ociImages: [VMEntry]
    public let fetchedAt: Date

    public init(from entries: [VMEntry], fetchedAt: Date = Date()) {
        self.localVMs = entries.filter(\.isLocal).sorted { $0.name < $1.name }
        self.ociImages = entries.filter { !$0.isLocal }.sorted { $0.name < $1.name }
        self.fetchedAt = fetchedAt
    }
}
