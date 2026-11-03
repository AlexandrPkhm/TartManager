import SwiftUI
import TartKit

/// Red deletion confirmation with the disk choice. The sheet renders only:
/// startability flows from `model.canDelete(vm:)` — the button never enables
/// into a silent no-op. Delete is not the default button, so Return cannot
/// delete a VM.
struct DeleteVMView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let vm: VMEntry
    @State private var removeDisk = true

    private var copy: DeleteVMCopy {
        DeleteVMCopy(removeDisk: removeDisk, keptDisksFolder: model.keptDisksFolder)
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
                Label(copy.warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Toggle(DeleteVMCopy.removeDiskLabel, isOn: $removeDisk)
                if let caption = copy.keptDiskCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
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
                    model.startDelete(vm: vm, removeDisk: removeDisk)
                    dismiss()
                }
                .keyboardShortcut(nil)
                .disabled(!model.canDelete(vm: vm))
            }
        }
    }
}
