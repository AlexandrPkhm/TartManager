import SwiftUI
import TartKit

struct CloneVMView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let source: VMEntry
    @State private var name = ""
    @State private var confirmingLowSpace = false

    var body: some View {
        Form {
            Section("Clone VM") {
                LabeledContent("Source") { Text(source.name) }
                TextField("New name", text: $name)
                if let issue = model.nameIssue(name) {
                    NameValidationLabel(text: issue)
                }
            }
            Section("Space") {
                LabeledContent("Free space in storage") {
                    Text(model.formattedFreeBytes)
                }
                LabeledContent("Estimated need") {
                    Text(estimatedNeedText)
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
                Button("Clone") { start() }
                    .disabled(!canStart)
            }
        }
        .confirmationDialog("Low disk space",
                            isPresented: $confirmingLowSpace,
                            titleVisibility: .visible) {
            Button("Clone Anyway") { model.startLocalClone(source: source, newName: name); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Free space is nearly exhausted; the copy may fail part-way.")
        }
        .onAppear { model.invalidateStorageProbeCache() }
    }

    private var canStart: Bool {
        !name.isEmpty && model.nameIssue(name) == nil
    }

    /// Estimate formatting calls the tested TartKit helper; the proceed/
    /// cancel decision (`cloneSpaceVerdict`) is owned by the model (finding 3).
    private var estimatedNeedText: String {
        let estimate = DiskSpacePolicy.localCloneEstimateBytes(for: source)
        guard estimate > 0 else { return "unknown (tart reports no size)" }
        return "~\(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)) full copy of “\(source.name)”"
    }

    private func start() {
        if model.cloneSpaceVerdict(for: source)?.isTight == true {
            confirmingLowSpace = true
        } else {
            model.startLocalClone(source: source, newName: name)
            dismiss()
        }
    }
}
