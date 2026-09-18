import SwiftUI
import TartKit

struct SnapshotCreateView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let vm: VMEntry
    @State private var label = ""
    @State private var confirmingLowSpace = false

    var body: some View {
        Form {
            Section("Take snapshot of “\(vm.name)”") {
                TextField("Label (optional)", text: $label)
            }
            Section("Space") {
                LabeledContent("Free space in snapshots folder") { Text(freeBytesText) }
                LabeledContent("Estimated archive") { Text(estimateText) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Take Snapshot") { start() }
                    .disabled(!model.checkSnapshotPossible(vm: vm))
            }
        }
        .confirmationDialog("Low disk space",
                            isPresented: $confirmingLowSpace,
                            titleVisibility: .visible) {
            Button("Take Snapshot Anyway") {
                model.createSnapshot(vm: vm, label: label.isEmpty ? nil : label)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The snapshots folder's volume is nearly full; the export may fail part-way.")
        }
    }

    private var assessment: AppModel.SnapshotSpaceAssessment {
        model.snapshotSpaceAssessment(vm: vm)
    }

    private var freeBytesText: String {
        guard let free = assessment.freeBytes else { return "unknown" }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }

    private var estimateText: String {
        guard let estimate = assessment.estimateBytes, estimate > 0 else { return "unknown" }
        return "~\(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)) "
             + "(the VM's on-disk size — a safe upper bound)"
    }

    private func start() {
        if assessment.verdict?.isTight == true {
            confirmingLowSpace = true
        } else {
            model.createSnapshot(vm: vm, label: label.isEmpty ? nil : label)
            dismiss()
        }
    }
}
