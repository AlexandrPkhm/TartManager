import SwiftUI

struct MainWindowRoot: View {
    let model: AppModel
    let reopener: MainWindowReopener
    @Binding var showingAbout: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView()
            .environmentObject(model)
            .environmentObject(model.stopCoordinator)
            .environmentObject(model.suspendCoordinator)
            .sheet(isPresented: $showingAbout) { AboutView() }
            .onAppear {
                reopener.register {
                    openWindow(id: MainWindowReopener.mainWindowSceneID)
                }
            }
            .onChange(of: model.appearance, initial: true) { _, appearance in
                NSApplication.shared.appearance = appearance.nativeAppearance
            }
    }
}
