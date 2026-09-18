import SwiftUI
import TartKit

/// Red typed-name deletion confirmation. The sheet renders only: the gate
/// itself is `TypedConfirmationGate` (shared with the model boundary
/// re-verification in `AppModel.startDelete`) and startability flows from
/// `model.canDelete(vm:)` — the button never enables into a silent no-op.
struct DeleteVMView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let vm: VMEntry
    @State private var typedName = ""

    private var confirmed: Bool {
        TypedConfirmationGate.allowsProceed(typedName: typedName, vmName: vm.name)
    }

    private var availabilityHint: String? {
        if !vm.isStoppedLocal {
            return "The VM must be stopped before it can be deleted."
        }
        if model.makeTartClient() == nil {
            return "Install tart (see banner) to delete VMs."
        }
        if case .unavailable = model.storageAvailability {
            return "VM storage is unavailable — delete cannot start."
        }
        return nil
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Delete VM") { Text(vm.name) }
                LabeledContent("Disk") {
                    Text(String(Int(vm.diskUsage)) + " GB on disk ("
                         + String(Int(vm.diskSize)) + " GB allocated)")
                }
            }
            Section {
                // Finding 6: the shared red typed-name confirmation section.
                DestructiveConfirmSection(
                    warning: "This permanently removes the VM and all of its data. "
                        + "Snapshots on the snapshots folder are not touched.",
                    prompt: "Type “\(vm.name)” to confirm",
                    typedName: $typedName)
                if let availabilityHint {
                    Label(availabilityHint, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Delete", role: .destructive) {
                    model.startDelete(vm: vm, confirmation: typedName)
                    dismiss()
                }
                .disabled(!confirmed || !model.canDelete(vm: vm))
            }
        }
    }
}
