import SwiftUI
import AppKit
import os
import TartKit

struct VMDetailSharedFoldersSection: View {
    @EnvironmentObject var model: AppModel
    let details: VMDetails
    @State private var draft: [VMFolderShare] = []
    /// Selection identity the draft was populated for (`name|state`).
    /// Deliberately excludes `fetchedAt`, so the ~3 s poll — which
    /// reassembles `VMDetails` with a fresh timestamp every cycle — never
    /// restarts population or wipes in-progress edits (8-AFK finding 2).
    @State private var loadedFor: String?
    /// True while the draft differs from the persisted store. Set only by
    /// user edits (through the row bindings), cleared by a successful
    /// `persist()` — programmatic repopulation never runs while dirty.
    @State private var isDirty = false
    @State private var invalidAlertMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if draft.isEmpty {
                WorkspaceEmptyState(symbol: "folder", title: "No shared folders",
                                    message: "Make a folder on your Mac available inside this VM.") {
                    Button { addFolder() } label: { Label("Add folder", systemImage: "plus") }
                        .disabled(!isEditable)
                }
            } else if isEditable {
                VStack(spacing: 14) {
                    ForEach($draft) { $share in
                        VMFolderShareRow(share: $share,
                                         onDirty: { isDirty = true },
                                         onEdit: { persist() },
                                         onRemove: { remove(share) })
                    }
                    .onMove { source, destination in
                        isDirty = true
                        draft.move(fromOffsets: source, toOffset: destination)
                        persist()
                    }
                }.padding(15).workspacePanel()
                Button { addFolder() } label: { Label("Add folder", systemImage: "plus") }
                    .buttonStyle(WorkspaceButtonStyle())
            } else {
                ForEach(draft) { share in
                    VMFolderShareSummary(share: share)
                }
            }
            if !isEditable {
                Label("Stop the VM to edit shared folders — changes apply at the next run.",
                      systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.muted)
            }
            if !draft.isEmpty { guidance }
        }
        .task(id: detailKey) { load() }
        .alert("Can't save shared folders",
               isPresented: Binding(
                   get: { invalidAlertMessage != nil },
                   set: { if !$0 { invalidAlertMessage = nil } })) {
            Button("OK") { invalidAlertMessage = nil }
        } message: {
            Text(invalidAlertMessage ?? "")
        }
    }

    /// The editability gate: 8-AFK's single source of truth plus the
    /// in-flight guard — never a re-derived state-string comparison
    /// (finding 6).
    private var isEditable: Bool {
        details.entry.canEditResources && !model.applyingResources
    }

    /// Identity key WITHOUT a timestamp (finding 4).
    private var detailKey: String {
        "\(details.entry.name)|\(details.entry.state)"
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Untagged shares are automatically mounted inside the guest at "
                 + "/Volumes/My Shared Files/<mount name>.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Custom-tag shares are not automounted. Mount one manually inside the guest with "
                 + "mount_virtiofs <tag> <directory>.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard loadedFor != detailKey else { return }
        loadedFor = detailKey
        if !isDirty { populate() }
    }

    private func populate() {
        draft = model.settings.sharedFolders(for: details.entry.name)
    }

    /// Every mutation (add, edit, move, remove) persists immediately —
    /// the section is only editable while the VM is stopped. Before saving,
    /// each row is re-validated through the model's own predicate: an
    /// ambiguous share can never be persisted, whatever path produced it
    /// (finding 5).
    private func persist() {
        let invalid = draft.filter { !$0.isValidForPersistence }
        guard invalid.isEmpty else {
            invalidAlertMessage = "A share name or mount tag is empty or contains "
                + "':' or ',' — tart cannot parse it. Fix the row first."
            let refusalLine = "refusing to persist \(draft.count) share(s) for "
                + "\(details.entry.name): \(invalid.count) invalid row(s)"
            Logger.sharedFolders.error("\(refusalLine, privacy: .public)")
            return
        }
        model.settings.setSharedFolders(draft, for: details.entry.name)
        isDirty = false
    }

    private func addFolder() {
        guard let path = FolderPicker.chooseFolder(title: "Choose a Folder to Share") else { return }
        do {
            draft.append(try VMFolderShare.makeDefault(hostPath: path))
            persist()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Can't share that folder"
            alert.informativeText = "Paths containing ':' or ',' are not supported by tart's share syntax."
            alert.runModal()
            Logger.sharedFolders.error(
                "folder picker path rejected for \(details.entry.name, privacy: .public)")
        }
    }

    private func remove(_ share: VMFolderShare) {
        isDirty = true
        draft.removeAll { $0.id == share.id }
        persist()
    }
}

private struct VMFolderShareRow: View {
    @Binding var share: VMFolderShare
    @State private var nameInput: String
    @FocusState private var nameIsFocused: Bool
    let onDirty: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    init(share: Binding<VMFolderShare>, onDirty: @escaping () -> Void,
         onEdit: @escaping () -> Void, onRemove: @escaping () -> Void) {
        _share = share
        _nameInput = State(initialValue: share.wrappedValue.name)
        self.onDirty = onDirty
        self.onEdit = onEdit
        self.onRemove = onRemove
    }

    var body: some View {
        // A shared trailing column keeps both editable fields the same width,
        // regardless of the intrinsic widths of Remove and Read-only.
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Mount name").font(.caption).foregroundStyle(.secondary)
                    TextField("e.g. Host Downloads", text: editableName)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .focused($nameIsFocused)
                        .onSubmit { nameInput = share.name }
                        .accessibilityLabel("Mount name")
                        .help("The folder name shown inside the guest. Leave the custom tag empty for automatic mounting.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) { onRemove() } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
                .buttonStyle(.borderless)
                .padding(.bottom, 3)
            }
            GridRow {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Host folder").font(.caption).foregroundStyle(.secondary)
                    Text(share.hostPath)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(share.hostPath)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // The path is read-only and must not widen the input column.
                .gridCellUnsizedAxes(.horizontal)
                Color.clear.frame(width: 0, height: 0)
            }
            GridRow(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Custom mount tag (optional)")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Leave empty to automount", text: optionalTag)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .accessibilityLabel("Custom mount tag (optional)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Read-only", isOn: readOnlyBinding)
                    .toggleStyle(.checkbox)
                    .padding(.bottom, 3)
            }
        }
        .font(.body)
        .padding(.vertical, 2)
        .onChange(of: share.name) { _, _ in onEdit() }
        .onChange(of: share.readOnly) { _, _ in onEdit() }
        .onChange(of: share.customTag) { _, _ in onEdit() }
        .onChange(of: nameIsFocused) { _, focused in
            if !focused { nameInput = share.name }
        }
    }

    /// Keep raw editing text so a trailing space survives long enough to type
    /// the next word. Only the normalized value reaches persistence and Tart.
    private var editableName: Binding<String> {
        Binding(
            get: { nameInput },
            set: { newValue in
                nameInput = newValue
                onDirty()
                share.set(name: newValue)
            })
    }

    /// `customTag` is optional; the field edits an empty-string view of it.
    /// Empty input clears the tag; otherwise spaces map to hyphens and the
    /// custom-tag charset rules apply.
    private var optionalTag: Binding<String> {
        Binding(
            get: { share.customTag ?? "" },
            set: { newValue in
                onDirty()
                share.set(customTag: newValue)
            })
    }

    private var readOnlyBinding: Binding<Bool> {
        Binding(
            get: { share.readOnly },
            set: { newValue in
                onDirty()
                share.readOnly = newValue
            })
    }
}

private struct VMFolderShareSummary: View {
    let share: VMFolderShare

    var body: some View {
        HStack {
            Image(systemName: "folder.badge.gearshape").foregroundStyle(.secondary)
            Text("\(share.name) ← \(share.hostPath)")
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            if share.readOnly {
                Text("read-only").font(.caption2).foregroundStyle(.secondary)
            }
            if let tag = share.customTag {
                Text("tag: \(tag)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
