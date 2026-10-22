import SwiftUI
import TartKit

struct StorageSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var validation: StorageValidation?
    @State private var snapshotValidation: StorageValidation?
    @State private var confirmingPrune = false
    @State private var prunePolicyForConfirmation: CachePrunePolicy = .manual
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
            SettingsPanel(title: "Maintenance") {
                LabeledContent("Automatic cache cleanup") {
                    Picker("Automatic cache cleanup",
                           selection: Binding(
                               get: { model.settings.cachePrunePolicy },
                               set: { model.setCachePrunePolicy($0) })) {
                        ForEach(CachePrunePolicy.allCases, id: \.self) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
                if let days = model.settings.cachePrunePolicy.retentionDays {
                    Text("Checks at launch and daily while Tart Manager is running, removing caches last accessed more than \(days) days ago.")
                        .font(.footnote)
                        .foregroundStyle(WorkspaceStyle.muted)
                } else {
                    Text("Keeps caches until you choose Prune Caches. Automatic cleanup is disabled.")
                        .font(.footnote)
                        .foregroundStyle(WorkspaceStyle.muted)
                }
                Button("Prune Caches…", role: .destructive) {
                    prunePolicyForConfirmation = model.settings.cachePrunePolicy
                    confirmingPrune = true
                }
            }
        }
        .confirmationDialog(
            pruneConfirmationTitle,
            isPresented: $confirmingPrune,
            titleVisibility: .visible) {
            Button("Prune Caches", role: .destructive) {
                model.startPrune(policy: prunePolicyForConfirmation)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes cached OCI image and IPSW data in the configured storage. "
                 + "You may need to download these images again. VMs and snapshots are not touched.")
        }
    }

    private var pruneConfirmationTitle: String {
        if let days = prunePolicyForConfirmation.retentionDays {
            return "Prune cache entries older than \(days) days?"
        }
        return "Prune all cached OCI image and IPSW data?"
    }

    private func choose() {
        guard let path = FolderPicker.chooseFolder(title: "Choose VM Storage") else { return }
        validation = model.attemptChooseStorage(path: path)
    }
}
