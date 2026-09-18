import SwiftUI
import TartKit

struct ReplaceDiskView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let vm: VMEntry
    @State private var imagePath = ""
    @State private var typedName = ""

    var body: some View {
        Form {
            Section("Replace disk of “\(vm.name)”") {
                // Finding 6: the shared red typed-name confirmation section;
                // the warning text is the tested pure ReplaceDiskCopy payload.
                DestructiveConfirmSection(
                    warning: ReplaceDiskCopy.lossWarning(for: vm.name),
                    prompt: ReplaceDiskCopy.confirmPrompt(for: vm.name),
                    typedName: $typedName)
            }
            Section("Replacement image") {
                HStack {
                    Text(imagePath.isEmpty
                         ? "No file chosen"
                         : (imagePath as NSString).lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") {
                        if let path = FilePicker.chooseFile(
                            title: "Choose a tart disk image (.img)",
                            // Finding 7: tart's --disk consumes raw .img disk
                            // images only — dmg is not a tart disk, and
                            // raw/qcow2 are unregistered, unsupported types.
                            allowedExtensions: ["img"]) {
                            imagePath = path
                        }
                    }
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
                Button("Replace Disk", role: .destructive) {
                    model.replaceDisk(vm: vm, path: imagePath, typedName: typedName)
                    dismiss()
                }
                // Findings 2/6: the enablement is the shared tested pure
                // RestoreGate — identical rule to the restore sheet.
                .disabled(imagePath.isEmpty
                          || !RestoreGate.allowsProceed(typedName: typedName,
                                                        vmName: vm.name))
            }
        }
    }
}
