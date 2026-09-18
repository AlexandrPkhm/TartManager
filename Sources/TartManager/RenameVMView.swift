import SwiftUI
import TartKit

/// Rename sheet: inline collision validation is UX (rendered from the
/// model's availability rules); the fresh-list pre-validation in `VMRename`
/// is the guard, and tart's rejections surface through the standard sheet.
struct RenameVMView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let vm: VMEntry
    @State private var newName: String

    init(vm: VMEntry) {
        self.vm = vm
        _newName = State(initialValue: vm.name)
    }

    private var nameHint: String? {
        guard !newName.isEmpty else { return nil }
        if newName != vm.name, !model.isNameAvailable(newName) {
            return "A VM, image, or running job with this name already exists."
        }
        if !vm.isStoppedLocal {
            return "The VM must be stopped before it can be renamed."
        }
        if model.makeTartClient() == nil {
            return "Install tart (see banner) to rename VMs."
        }
        if case .unavailable = model.storageAvailability {
            return "VM storage is unavailable — rename cannot start."
        }
        return nil
    }

    var body: some View {
        Form {
            Section("Rename VM") {
                TextField("New name", text: $newName)
                if let nameHint {
                    Label(nameHint, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Rename") {
                    Task { await model.rename(vm: vm, to: newName) }
                    dismiss()
                }
                .disabled(!model.canRename(vm: vm, to: newName))
            }
        }
    }
}
