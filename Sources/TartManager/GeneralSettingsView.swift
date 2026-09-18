import SwiftUI
import TartKit

/// General settings: the SSH username used by the detail pane's
/// "copy ssh command" button (configurable).
struct GeneralSettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            TextField("SSH username", text: Binding(
                get: { model.settings.sshUser },
                set: { model.settings.sshUser = $0 }))
            .textFieldStyle(.roundedBorder)
            Text("Used for the “copy ssh command” button in the VM detail pane. Defaults to admin.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 400)
    }
}
