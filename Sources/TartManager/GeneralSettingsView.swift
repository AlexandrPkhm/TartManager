import SwiftUI
import TartKit

/// General settings for appearance and the detail pane's SSH command.
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
        }
    }
}
