import SwiftUI

struct MainWindowRoot: View {
    let model: AppModel
    let applicationActivationPolicy: ApplicationActivationPolicy
    @Binding var showingAbout: Bool

    var body: some View {
        ContentView()
            .environmentObject(model)
            .environmentObject(model.stopCoordinator)
            .environmentObject(model.suspendCoordinator)
            .sheet(isPresented: $showingAbout) { AboutView() }
            .onDisappear { applicationActivationPolicy.mainWindowDidClose() }
    }
}
