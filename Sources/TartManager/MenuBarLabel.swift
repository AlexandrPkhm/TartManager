import SwiftUI

/// The menu-bar extra's icon. It is the only SwiftUI view that stays alive in
/// menu-bar-only mode, so it registers the main-window opener that a Dock
/// reopen uses.
struct MenuBarLabel: View {
    let applicationActivationPolicy: ApplicationActivationPolicy
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarIcon.image)
            .accessibilityLabel("Tart Manager")
            .onAppear {
                applicationActivationPolicy.registerMainWindowOpener {
                    openWindow(id: ApplicationActivationPolicy.mainWindowSceneID)
                }
            }
    }
}
