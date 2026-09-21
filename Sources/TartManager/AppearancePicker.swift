import SwiftUI
import TartKit

extension AppAppearance {
    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// AppKit appearance also covers native windows, sheets, and dynamic colors.
    /// nil removes the override so macOS changes are followed automatically.
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Both settings and the toolbar edit the same published, persisted preference.
struct AppearancePicker: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Picker("Appearance", selection: $model.appearance) {
            ForEach(AppAppearance.allCases, id: \.self) { appearance in
                Label(appearance.title, systemImage: appearance.symbol)
                    .tag(appearance)
            }
        }
    }
}
