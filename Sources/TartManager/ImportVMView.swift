import SwiftUI
import TartKit

struct ImportVMView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let path: String
    @State private var name: String
    @State private var confirmingLowSpace = false

    init(path: String, suggestedName: String) {
        self.path = path
        _name = State(initialValue: suggestedName)
    }

    var body: some View {
        Form {
            Section("Import VM") {
                LabeledContent("Archive") {
                    Text((path as NSString).lastPathComponent)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                TextField("New name", text: $name)
                if let nameHint {
                    Label(nameHint, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            Section("Space") {
                LabeledContent("Free space in storage") { Text(freeBytesText) }
                LabeledContent("Estimated need") { Text(estimateText) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") { start() }
                    .disabled(!model.canImport(name: name))
            }
        }
        .confirmationDialog("Low disk space",
                            isPresented: $confirmingLowSpace,
                            titleVisibility: .visible) {
            Button("Import Anyway") { startImport(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Free space is nearly exhausted; the import may fail part-way.")
        }
    }

    /// Reasons the Import button stays disabled — the gate mirrors
    /// `model.canImport` (client, storage, name incl. in-flight targets).
    private var nameHint: String? {
        guard !name.isEmpty else { return nil }
        if !model.isNameAvailable(name) {
            return "A VM, image, or running job with this name already exists."
        }
        if model.makeTartClient() == nil {
            return "Install tart (see banner) to import."
        }
        if case .unavailable = model.storageAvailability {
            return "VM storage is unavailable — import cannot start."
        }
        return nil
    }

    private var assessment: AppModel.ImportSpaceAssessment {
        model.importPreflight(path: path)
    }

    private var estimateText: String {
        guard let estimate = assessment.estimateBytes else { return "unknown" }
        return "~\(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)) unpacked"
    }

    private var freeBytesText: String {
        guard let free = assessment.freeBytes else { return "unknown" }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }

    private func start() {
        if assessment.needsConfirmation {
            confirmingLowSpace = true
        } else {
            startImport()
        }
    }

    private func startImport() {
        model.startImport(path: path, name: name)
        dismiss()
    }
}
