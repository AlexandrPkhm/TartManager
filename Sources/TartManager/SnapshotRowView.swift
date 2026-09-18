import SwiftUI
import TartKit

struct SnapshotRowView: View {
    @EnvironmentObject var model: AppModel
    let snapshot: Snapshot
    let entry: VMEntry

    var body: some View {
        HStack {
            Image(systemName: "externaldrive.badge.timemachine").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.label ?? (snapshot.archivePath as NSString).lastPathComponent)
                Text("\(snapshot.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "") · \(ByteCountFormatter.string(fromByteCount: snapshot.sizeBytes, countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.pendingRestore = AppModel.PendingSnapshotRestore(vm: entry, snapshot: snapshot)
            } label: {
                Label("Restore", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .disabled(!model.checkRestorePossible(vm: entry))
            .help(entry.running
                  ? "Stop the VM to restore a snapshot"
                  : "Restore this snapshot")
            Button(role: .destructive) {
                deleteTarget = snapshot
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .confirmationDialog(
            "Delete snapshot “\(snapshot.label ?? "unnamed")”?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible) {
                Button("Delete Snapshot", role: .destructive) {
                    if let target = deleteTarget {
                        Task { await model.deleteSnapshot(target) }
                    }
                    deleteTarget = nil
                }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("The archive file is removed permanently. This cannot be undone.")
            }
        .onAppear { deleteTarget = nil }
    }

    @State private var deleteTarget: Snapshot?
}
