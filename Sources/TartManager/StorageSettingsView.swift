import SwiftUI
import TartKit

struct StorageSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var validation: StorageValidation?
    @State private var snapshotValidation: StorageValidation?
    @State private var confirmingPrune = false
    @State private var prunePolicyForConfirmation: CachePrunePolicy = .manual

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
                        Text(reason).foregroundStyle(WorkspaceStyle.error)
                    }
                }
            }
            RegistrySettingsPanel()
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
                    Text(reason).foregroundStyle(WorkspaceStyle.error)
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
