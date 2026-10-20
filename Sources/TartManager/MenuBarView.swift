import AppKit
import SwiftUI
import TartKit

struct MenuBarView: View {
    let applicationActivationPolicy: ApplicationActivationPolicy
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Tart Manager") {
            revealMainWindow()
        }
        Divider()
        vmMenuContent
        Divider()
        Button("Refresh List") {
            Task { await model.inventoryService.refresh() }
        }
        .disabled(!canControlVMs)
        Divider()
        if UpdateStatusCopy(status: model.updateStatus).showsMenuBarItem {
            Button(UpdateStatusCopy.menuBarItemLabel) {
                model.checkForUpdates()
            }
            Divider()
        }
        SettingsLink {
            Text("Settings…")
        }
        Divider()
        Button("Quit Tart Manager") {
            NSApp.terminate(nil)
        }
    }

    @ViewBuilder private var vmMenuContent: some View {
        if model.requiresOnboarding {
            Text("Configure VM storage in Settings to manage VMs.")
        } else if !canControlVMs {
            Text("tart is unavailable. Open Tart Manager to check setup.")
        } else if let inventory = model.inventory {
            if inventory.localVMs.isEmpty {
                Text("No local virtual machines")
            } else {
                ForEach(inventory.localVMs) { vm in
                    vmMenu(for: vm)
                }
            }
        } else {
            Text("Loading virtual machines…")
        }
    }

    private func vmMenu(for vm: VMEntry) -> some View {
        Menu(vm.name) {
            Text("Status: \(vm.state.capitalized)")
            Divider()
            ForEach(MenuBarVMAction.actions(for: vm), id: \.self) { action in
                Button(action.title) {
                    revealMainWindow(selecting: vm)
                    Task { await perform(action, for: vm) }
                }
            }
            Divider()
            Button("Show in Tart Manager") {
                revealMainWindow(selecting: vm)
            }
        }
    }

    private var canControlVMs: Bool {
        model.storageAvailability.isAvailable && model.prerequisite?.isSatisfied == true
    }

    private func perform(_ action: MenuBarVMAction, for vm: VMEntry) async {
        switch action {
        case .run:
            await model.requestRun(vm: vm)
        case .stop:
            await model.stop(vm: vm)
        case .suspend:
            await model.suspend(vm: vm)
        }
    }

    private func revealMainWindow(selecting vm: VMEntry? = nil) {
        if let vm {
            model.select(vm)
        }
        applicationActivationPolicy.openMainWindow {
            openWindow(id: ApplicationActivationPolicy.mainWindowSceneID)
        }
    }
}
