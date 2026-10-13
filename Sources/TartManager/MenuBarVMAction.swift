import TartKit

/// The one lifecycle action a menu-bar item may expose for a local VM.
/// This pure mapping keeps SwiftUI state branching testable.
enum MenuBarVMAction: Equatable, Hashable {
    case run(title: String)
    case stop
    case suspend

    init?(entry: VMEntry) {
        guard entry.isLocal else { return nil }
        if entry.running {
            self = .stop
        } else {
            self = .run(title: entry.primaryActionLabel(
                distinguishesSuspended: SuspendedStateReporting.distinguishesSuspended))
        }
    }

    var title: String {
        switch self {
        case .run(let title): return title
        case .stop: return "Stop"
        case .suspend: return "Suspend"
        }
    }

    static func actions(for entry: VMEntry) -> [MenuBarVMAction] {
        guard let primaryAction = Self(entry: entry) else { return [] }
        var actions = [primaryAction]
        if entry.canSuspend {
            actions.append(.suspend)
        }
        return actions
    }
}
