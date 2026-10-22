import Foundation

/// Where the active tart binary comes from.
///
/// `bundled` is the `tart.app` inside the Tart Manager bundle; `installed` is
/// a tart on this Mac (detected, or a custom path). The raw values are the
/// persisted `AppSettings.tartSource` values.
public enum TartSource: String, Equatable, Sendable {
    case bundled
    case installed
}
