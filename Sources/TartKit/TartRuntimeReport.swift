import Foundation

/// Both tart sources, checked together, and the one in use.
///
/// The checker checks both sources unless the selected bundled tart works,
/// so the banner can offer a switch when the active tart fails.
/// `bundled == nil` means this build has no bundled tart (for example,
/// `swift run`). `installed == nil` means the checker did not look for the
/// installed tart, because the selected bundled tart works.
public struct TartRuntimeReport: Equatable, Sendable {
    public let bundled: TartPrerequisiteStatus?
    public let installed: TartPrerequisiteStatus?
    public let selected: TartSource
    /// The stored preference at check time; `nil` means none was stored.
    public let storedPreference: TartSource?

    public init(bundled: TartPrerequisiteStatus?,
                installed: TartPrerequisiteStatus?,
                selected: TartSource,
                storedPreference: TartSource?) {
        self.bundled = bundled
        self.installed = installed
        self.selected = selected
        self.storedPreference = storedPreference
    }

    /// The selected source's status. A selected but absent bundled tart is
    /// `.missing(.bundled)`: the app never falls back to the other source.
    public var active: TartPrerequisiteStatus {
        switch selected {
        case .bundled: return bundled ?? .missing(source: .bundled)
        case .installed: return installed ?? .missing(source: .installed)
        }
    }

    /// The unselected source's status; `nil` when it is the absent bundled
    /// tart or the installed tart that the checker did not look for.
    public var other: TartPrerequisiteStatus? {
        switch selected {
        case .bundled: return installed
        case .installed: return bundled
        }
    }

    /// The same statuses with another source selected, without a re-check.
    /// The stored preference becomes `source`.
    public func selecting(_ source: TartSource) -> TartRuntimeReport {
        TartRuntimeReport(bundled: bundled, installed: installed,
                          selected: source, storedPreference: source)
    }
}
