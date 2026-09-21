import SwiftUI
import TartKit

/// General settings for appearance and the detail pane's SSH command.
struct GeneralSettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Appearance") {
                AppearancePicker()
                    .pickerStyle(.menu)
                Text("System follows your Mac's appearance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Connection") {
                TextField("SSH username", text: Binding(
                    get: { model.settings.sshUser },
                    set: { model.settings.sshUser = $0 }))
                .textFieldStyle(.roundedBorder)
                Text("Used for the “copy ssh command” button in the VM detail pane. Defaults to admin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
