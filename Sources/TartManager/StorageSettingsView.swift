import SwiftUI
import TartKit

struct StorageSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var validation: StorageValidation?
    @State private var snapshotValidation: StorageValidation?
    @State private var confirmingPrune = false
    @State private var registryHost = "ghcr.io"
    @State private var registryUsername = ""
    @State private var registryPassword = ""

    /// tart (or the storage configuration) unavailable: both buttons are
    /// disabled and the footnote explains why — no click can dead-end
    /// silently.
    private var tartUnavailable: Bool { model.makeTartClient() == nil }

    var body: some View {
        SettingsPage {
            SettingsPanel {
                LabeledContent("VM storage") {
                    Text(model.settings.storagePath ?? "(not set)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(WorkspaceStyle.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.settings.storagePath ?? "Not configured")
                        .textSelection(.enabled)
                }
                HStack {
                    Button("Choose…") { choose() }
                    if let validation, case .invalid(_, let reason) = validation {
                        Text(reason).foregroundStyle(.red)
                    }
                }
            }
            SettingsPanel(title: "Registries") {
                LabeledContent("Host") {
                    TextField("e.g. ghcr.io", text: $registryHost)
                        .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 280)
                }
                LabeledContent("Username") {
                    TextField("Username", text: $registryUsername)
                        .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 280)
                }
                LabeledContent("Password / token") {
                    SecureField("Password / token", text: $registryPassword)
                        .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 280)
                }
                if !RegistryCredentialRules.isValidHost(registryHost) {
                    Text("The host must not start with “-” or contain spaces.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button("Sign In") {
                        // Snapshot BEFORE the Task: the Task body runs
                        // asynchronously and would read the cleared @State
                        // values; the captured locals live exactly as long as
                        // the operation, and the UI state is cleared
                        // synchronously — the secret never lingers.
                        let host = registryHost
                        let username = registryUsername
                        let password = registryPassword
                        registryPassword = ""
                        Task {
                            await model.registryLogin(host: host,
                                                      username: username,
                                                      password: password)
                        }
                    }
                    .disabled(model.registryOperationInFlight
                              || tartUnavailable
                              || !RegistryCredentialRules.isValidHost(registryHost)
                              || registryUsername.isEmpty
                              || registryPassword.isEmpty)
                    Spacer()
                    Button("Sign Out", role: .destructive) {
                        let host = registryHost
                        Task { await model.registryLogout(host: host) }
                    }
                    .disabled(model.registryOperationInFlight
                              || tartUnavailable
                              || !RegistryCredentialRules.isValidHost(registryHost))
                }
                Text("Signing in stores the credentials in tart's macOS Keychain, not in Tart Manager. tart can't list logged-in hosts, so sessions aren't shown here — sign in or out per host.")
                    .font(.footnote)
                    .foregroundStyle(WorkspaceStyle.muted)
                if tartUnavailable {
                    Text("Registry sign-in is disabled while tart or the storage configuration is unavailable.")
                        .font(.footnote)
                        .foregroundStyle(WorkspaceStyle.muted)
                }
            }
            SettingsPanel(title: "Snapshots") {
                LabeledContent("Snapshots") {
                    if let folder = model.resolvedSnapshotsFolder {
                        Text(folder)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(WorkspaceStyle.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(folder)
                            .textSelection(.enabled)
                    } else {
                        Text("(not set — choose VM storage first)")
                            .foregroundStyle(WorkspaceStyle.muted)
                    }
                }
                Button("Choose Snapshots Folder…") {
                    if let path = FolderPicker.chooseFolder(title: "Choose Snapshots Folder") {
                        let result = StorageLocationValidator.validate(path)
                        switch result {
                        case .valid(let validPath):
                            model.settings.snapshotsFolder = validPath
                            snapshotValidation = nil
                        case .invalid(let invalidPath, let reason):
                            snapshotValidation = StorageValidation.invalid(path: invalidPath, reason: reason)
                        }
                    }
                }
                if let snapshotValidation, case .invalid(_, let reason) = snapshotValidation {
                    Text(reason).foregroundStyle(.red)
                }
            }
            SettingsPanel {
                LabeledContent("Detected tart") {
                    if let status = model.prerequisite, case .ok(let version, _) = status {
                        Text(verbatim: "\(version)")
                    } else if let status = model.prerequisite, case .outdated(let found, _, _) = status {
                        Text(verbatim: "\(found) (update required)").foregroundStyle(.orange)
                    } else {
                        Text("not found").foregroundStyle(.red)
                    }
                }
                Button("Re-check") { model.checkPrerequisite() }
            }
            SettingsPanel(title: "Maintenance") {
                LabeledContent("Prune caches older than") {
                    Picker("Prune caches older than",
                           selection: Binding(
                               get: { model.settings.pruneRetentionDays },
                               set: { model.settings.pruneRetentionDays = $0 })) {
                        ForEach(AppSettings.pruneRetentionChoices, id: \.self) { days in
                            Text("\(days) days").tag(days)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                Button("Prune Caches…", role: .destructive) {
                    confirmingPrune = true
                }
            }
        }
        .confirmationDialog(
            "Prune cache entries older than \(model.settings.pruneRetentionDays) days?",
            isPresented: $confirmingPrune,
            titleVisibility: .visible) {
            Button("Prune Caches", role: .destructive) {
                model.startPrune(days: model.settings.pruneRetentionDays)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes cached OCI image and IPSW data in the configured storage. "
                 + "VMs and snapshots are not touched. The job appears in the Jobs list "
                 + "with its summary when done.")
        }
    }

    private func choose() {
        guard let path = FolderPicker.chooseFolder(title: "Choose VM Storage") else { return }
        validation = model.attemptChooseStorage(path: path)
    }
}
