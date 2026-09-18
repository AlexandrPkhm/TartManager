import SwiftUI

@main
struct TartManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1024, height: 640)
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
