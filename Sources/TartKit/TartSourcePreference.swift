import Foundation

/// The stored tart choice that `PrerequisiteChecker` resolves.
///
/// `source == nil` means no preference is stored yet; the checker then
/// selects `installed`. `customPath` applies only to the `installed` source.
public struct TartSourcePreference: Equatable, Sendable {
    public let source: TartSource?
    public let customPath: String?

    public init(source: TartSource?, customPath: String?) {
        self.source = source
        self.customPath = customPath
    }
}
