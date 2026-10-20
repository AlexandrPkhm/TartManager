import SwiftUI
import AppKit
import TartKit

/// Dedicated empty state when the configured storage is unreachable
/// (missing volume or read-only mount). Reads the availability value from
/// the model rather than a path string, so the copy can reflect the reason.
struct StorageUnavailableView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let (path, reason) = unavailableDetails
        let copy = StorageUnavailableCopy(reason: reason)
        VStack(spacing: 0) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 26))
                .foregroundStyle(WorkspaceStyle.warning)
                .frame(width: 64, height: 64)
                .background(WorkspaceStyle.warningBackground, in: Circle())
                .padding(.bottom, 16)
            Text(StorageUnavailableCopy.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WorkspaceStyle.text)
                .padding(.bottom, 6)
            Text(copy.headline)
                .font(.system(size: 13))
                .foregroundStyle(WorkspaceStyle.muted)
                .padding(.bottom, 14)
            pathChip(path)
                .padding(.bottom, 14)
            Text(copy.hint)
                .font(.system(size: 13))
                .foregroundStyle(WorkspaceStyle.muted)
                .padding(.bottom, 20)
            HStack(spacing: 10) {
                Button { chooseAnother() } label: {
                    Label("Choose Another Folder…", systemImage: "folder")
                }
                .buttonStyle(WorkspaceButtonStyle())
                Button { model.refreshAvailability() } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(WorkspaceButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
            }
            .fixedSize()
            .padding(.bottom, 14)
            Text(StorageUnavailableCopy.autoRetryNote)
                .font(.system(size: 11))
                .foregroundStyle(WorkspaceStyle.muted)
        }
        .multilineTextAlignment(.center)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkspaceStyle.background)
    }

    private func pathChip(_ path: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").foregroundStyle(WorkspaceStyle.muted)
            Text(path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(WorkspaceStyle.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            CopyButton(value: path, systemImage: "doc.on.doc")
                .buttonStyle(.plain)
                .foregroundStyle(WorkspaceStyle.muted)
                .help("Copy path")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: 480)
        .fixedSize(horizontal: false, vertical: true)
        .workspacePanel()
    }

    private var unavailableDetails: (path: String, reason: StorageUnavailableReason) {
        if case .unavailable(let path, let reason) = model.storageAvailability {
            return (path, reason)
        }
        return (StorageLocationValidator.defaultPath, .missing)
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
