import SwiftUI
import TartKit

struct RestoreSnapshotView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let pending: AppModel.PendingSnapshotRestore
    @State private var typedName = ""
    @State private var useSafety = true

    var body: some View {
        Form {
            Section("Restore snapshot") {
                LabeledContent("VM") { Text(pending.vm.name) }
                LabeledContent("Snapshot") {
                    Text(pending.snapshot.label
                         ?? (pending.snapshot.archivePath as NSString).lastPathComponent)
                }
                LabeledContent("Taken") {
                    Text(pending.snapshot.createdAt?
                            .formatted(date: .abbreviated, time: .shortened) ?? "unknown")
                }
            }
            Section("Safety") {
                Toggle("Snapshot the current state first", isOn: $useSafety)
                Text("Recommended: before replacing the VM, its current state is saved "
                     + "as a normal snapshot you can restore if the rollback was a mistake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                // Finding 6: the shared typed-name confirmation section; the
                // restore gate remains the tested pure RestoreGate.
                DestructiveConfirmSection(
                    warning: nil,
                    prompt: "Type “\(pending.vm.name)” to confirm",
                    typedName: $typedName)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Restore", role: .destructive) {
                    model.restore(snapshot: pending.snapshot, vm: pending.vm, useSafety: useSafety)
                    dismiss()
                }
                // The typed-name gate is the tested pure function.
                .disabled(!RestoreGate.allowsProceed(typedName: typedName,
                                                     vmName: pending.vm.name))
            }
        }
    }
}
