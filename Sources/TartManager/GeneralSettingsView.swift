import SwiftUI
import TartKit

/// General settings for appearance, the detail pane's SSH command, and
/// automatic update checks.
struct GeneralSettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        SettingsPage {
            SettingsPanel(title: "Appearance") {
                LabeledContent("Appearance") {
                    AppearancePicker()
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                }
                WorkspaceStyle.line.frame(height: 1)
                Text("System follows your Mac's appearance.")
                    .font(.caption)
                    .foregroundStyle(WorkspaceStyle.muted)
            }
            SettingsPanel(title: "Connection") {
                LabeledContent("SSH username") {
                    TextField("SSH username", text: Binding(
                        get: { model.settings.sshUser },
                        set: { model.settings.sshUser = $0 }))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }
                WorkspaceStyle.line.frame(height: 1)
                Text("Used for the “copy ssh command” button in the VM detail pane. Defaults to admin.")
                    .font(.caption)
                    .foregroundStyle(WorkspaceStyle.muted)
            }
            SettingsPanel(title: "Updates") {
                LabeledContent("Check for updates automatically") {
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { model.automaticUpdateChecks },
                        set: { model.automaticUpdateChecks = $0 }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(model.updateStatus == .unavailable)
                }
            }
        }
    }
}
