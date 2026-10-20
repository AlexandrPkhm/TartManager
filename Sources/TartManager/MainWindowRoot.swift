import SwiftUI

struct MainWindowRoot: View {
    let model: AppModel
    let applicationActivationPolicy: ApplicationActivationPolicy

    var body: some View {
        ContentView()
            .environmentObject(model)
            .environmentObject(model.stopCoordinator)
            .environmentObject(model.suspendCoordinator)
            .onDisappear { applicationActivationPolicy.mainWindowDidClose() }
    }
}
