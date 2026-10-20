import SwiftUI

@main
struct TartManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    private var applicationActivationPolicy: ApplicationActivationPolicy {
        appDelegate.applicationActivationPolicy
    }

    var body: some Scene {
        WindowGroup(id: ApplicationActivationPolicy.mainWindowSceneID) {
            MainWindowRoot(
                model: model,
                applicationActivationPolicy: applicationActivationPolicy
            )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1024, height: 640)
        .commands {
            CommandGroup(replacing: .appInfo) {
                AboutCommandButton()
                    .environmentObject(model)
            }
        }
        MenuBarExtra {
            MenuBarView(applicationActivationPolicy: applicationActivationPolicy)
                .environmentObject(model)
        } label: {
            MenuBarLabel(applicationActivationPolicy: applicationActivationPolicy)
        }
        .menuBarExtraStyle(.menu)
        Settings {
            TabView(selection: $model.selectedSettingsTab) {
                GeneralSettingsView()
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsTab.general)
                StorageSettingsView()
                    .tabItem { Label("Storage", systemImage: "externaldrive") }
                    .tag(SettingsTab.storage)
                AboutSettingsView()
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag(SettingsTab.about)
            }
            .frame(width: 640, height: model.selectedSettingsTab.frameHeight)
            .background(WorkspaceStyle.background)
            .foregroundStyle(WorkspaceStyle.text)
            .tint(WorkspaceStyle.accent)
            .toolbarBackground(WorkspaceStyle.panel, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }
}
