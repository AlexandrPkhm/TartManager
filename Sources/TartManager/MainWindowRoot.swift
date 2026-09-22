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
            .onChange(of: model.appearance, initial: true) { _, appearance in
                NSApplication.shared.appearance = appearance.nativeAppearance
            }
    }
}
