import SwiftUI
import TartKit

/// First-run sheet: choose where tart VMs live.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var validation: StorageValidation?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "externaldrive.badge.timemachine")
                .font(.system(size: 56))
            Text("Where should Tart Manager look for VMs?")
                .font(.title2).bold()
            Text("Pick the folder that holds your tart VMs (tart's home). "
                 + "For example a folder on an external SSD. You can change it later in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Choose Folder…") { choose() }
                    .buttonStyle(.borderedProminent)
                Button("Use Default (\(StorageLocationValidator.defaultPath))") { useDefault() }
            }
            if let validation, case .invalid(_, let reason) = validation {
                Text(reason).foregroundStyle(.red).font(.callout)
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    private func choose() {
        guard let path = FolderPicker.chooseFolder(title: "Choose VM Storage") else { return }
        apply(path)
    }

    private func useDefault() {
        // The default (~/.tart) may not exist yet on a fresh machine.
        // The mutation happens in TartKit; the view only reacts to errors.
        let path = StorageLocationValidator.defaultPath
        do {
            try StorageLocationValidator.ensureDefaultExists()
        } catch {
            validation = .invalid(path: path,
                reason: "Could not create the default folder: \(error.localizedDescription)")
            return
        }
        apply(path)
    }

    private func apply(_ path: String) {
        let result = model.attemptChooseStorage(path: path)
        validation = result
        if result.isValid {
            // Explicit dismissal: the sheet is `.interactiveDismissDisabled()`,
            // so without this call a valid choice would leave it stuck on
            // screen and the app unreachable.
            dismiss()
        }
    }
}
