import SwiftUI

struct MainWindowRoot: View {
    let model: AppModel
    let applicationActivationPolicy: ApplicationActivationPolicy
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .environmentObject(model)
            .environmentObject(model.stopCoordinator)
            .environmentObject(model.suspendCoordinator)
            .onAppear {
                applicationActivationPolicy.mainWindowDidOpen()
                // A second registration source in case the menu-bar label
                // never appears.
                applicationActivationPolicy.registerMainWindowOpener {
                    openWindow(id: ApplicationActivationPolicy.mainWindowSceneID)
                }
            }
            .onDisappear { applicationActivationPolicy.mainWindowDidClose() }
    }
}
