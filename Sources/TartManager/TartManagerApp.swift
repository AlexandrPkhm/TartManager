import SwiftUI

@main
struct TartManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @State private var mainWindowReopener = MainWindowReopener()
    @State private var showingAbout = false
    @State private var settingsTab: SettingsTab = .general

    private enum SettingsTab { case general, storage }

    var body: some Scene {
        WindowGroup(id: MainWindowReopener.mainWindowSceneID) {
            MainWindowRoot(
                model: model,
                reopener: mainWindowReopener,
                showingAbout: $showingAbout
            )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1024, height: 640)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Tart Manager") { showingAbout = true }
            }
        }
        Settings {
            TabView(selection: $settingsTab) {
                GeneralSettingsView()
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsTab.general)
                StorageSettingsView()
                    .tabItem { Label("Storage", systemImage: "externaldrive") }
                    .tag(SettingsTab.storage)
            }
            .frame(width: 640, height: settingsTab == .general ? 320 : 620)
            .environmentObject(model)
            // Settings remains usable when all main windows are closed.
            .onChange(of: model.appearance, initial: true) { _, appearance in
                NSApplication.shared.appearance = appearance.nativeAppearance
            }
        }
        .windowResizability(.contentSize)
    }
}
