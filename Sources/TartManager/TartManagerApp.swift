import SwiftUI

@main
struct TartManagerApp: App {
    @StateObject private var model = AppModel()
    @State private var showingAbout = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.stopCoordinator)
                .environmentObject(model.suspendCoordinator)
                .sheet(isPresented: $showingAbout) { AboutView() }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Tart Manager") { showingAbout = true }
            }
        }
        Settings {
            StorageSettingsView()
                .environmentObject(model)
            GeneralSettingsView()
                .environmentObject(model)
        }
    }
}
