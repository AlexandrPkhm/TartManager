import SwiftUI
import AppKit
import TartKit

/// Dedicated empty state when the configured storage is unreachable
/// (missing volume or read-only mount). Reads the availability value from
/// the model rather than a path string, so the copy can reflect the reason.
struct StorageUnavailableView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ContentUnavailableView {
            Label("VM storage unavailable", systemImage: "externaldrive.badge.xmark")
        } description: {
            Text(descriptionText)
        } actions: {
            HStack {
                Button("Choose Another Folder…") { chooseAnother() }
                Button("Retry") { model.refreshAvailability() }
            }
        }
    }

    private var currentAvailability: StorageAvailability {
        if !model.storageAvailability.isAvailable { return model.storageAvailability }
        return .unavailable(path: StorageLocationValidator.defaultPath, reason: .missing)
    }

    private var descriptionText: String {
        switch currentAvailability {
        case .available:
            return ""
        case .unavailable(let path, let reason):
            switch reason {
            case .missing:
                return "The configured VM storage can't be reached:\n\(path)\n\n"
                     + "Mount the volume, or choose another folder."
            case .notWritable:
                return "The configured VM storage exists but is not writable:\n\(path)\n\n"
                     + "Fix the folder's permissions, or choose another folder."
            }
        }
    }

    private func chooseAnother() {
        guard let path = FolderPicker.chooseFolder(title: "Choose VM Storage") else { return }
        let result = model.attemptChooseStorage(path: path)
        if case .invalid(_, let reason) = result {
            let alert = NSAlert()
            alert.messageText = "Can't use that folder"
            alert.informativeText = reason
            alert.runModal()
        }
    }
}
