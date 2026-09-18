import SwiftUI
import TartKit

/// The single modal the root view presents. SwiftUI honors one `.sheet`
/// modifier per view node, so onboarding and the error report share this
/// item-driven presentation instead of stacking a second `.sheet` on the
/// view that already presents onboarding.
enum RootSheet: Identifiable {
    case onboarding
    case errorReport(TartOperationError)
    case createVM
    case importVM(path: String, suggestedName: String)

    var id: String {
        switch self {
        case .onboarding: return "onboarding"
        case .errorReport(let error): return "error-\(error.id.uuidString)"
        case .createVM: return "create-vm"
        case .importVM: return "import-vm"
        }
    }
}
