import SwiftUI
import TartKit

struct VMDetailSettingsSection: View {
    @EnvironmentObject var model: AppModel
    let details: VMDetails
    let host: HostFacts

    @State private var cpuText = ""
    @State private var memoryMBText = ""
    @State private var diskText = ""
    @State private var displayText = ""
    /// Tri-state refit: nil = "leave as configured" (nothing sent). The
    /// Toggle starts from the live config's fit state until the user actually
    /// toggles it, at which point the override becomes non-nil.
    @State private var refitOverride: Bool? = nil
    /// Selection identity the fields were populated for (name|state).
    /// Deliberately excludes `fetchedAt`, so the ~3 s poll never restarts
    /// population or wipes in-progress edits.
    @State private var loadedFor: String?
    /// True while the user has modified any field since the last populate.
    @State private var isDirty = false

    var body: some View {
        Group {
            Section("Resources") {
                if isEditable {
                    editor
                } else {
                    Label(hintText, systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            // Sibling section (not nested inside "Resources"), same editability
            // gating.
            if details.entry.isLocal && isEditable {
                Section("Hardware identity") {
                    Button("Regenerate MAC Address") {
                        Task { await model.regenerateMAC(for: details.entry) }
                    }
                    .disabled(model.applyingResources)
                    Button("Regenerate Serial Number") {
                        Task { await model.regenerateSerial(for: details.entry) }
                    }
                    .disabled(model.applyingResources || !serialRegenerationAvailable)
                    if !serialRegenerationAvailable {
                        Text("Regenerating the serial number is only available for macOS guests; tart leaves other guests unchanged.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task(id: detailKey) { load() }
        .onChange(of: details.config) { _, _ in
            // Repopulate on real config changes (successful apply, external
            // edits) — but never while the user is mid-edit.
            if !isDirty { populate() }
        }
    }

    // MARK: Editability

    /// Editing requires a local stopped (non-suspended) VM, an available tart
    /// client (the editor is inert — not silently no-op — otherwise), and no
    /// in-flight operation.
    private var isEditable: Bool {
        details.entry.isLocal
            && details.entry.canEditResources
            && model.makeTartClient() != nil
            && !model.applyingResources
    }

    private var hintText: String {
        if !details.entry.isLocal { return "Only local VMs have editable settings." }
        if !details.entry.canEditResources { return "Stop the VM to edit its settings." }
        if model.makeTartClient() == nil { return "Install tart (see banner) to edit settings." }
        return "Another tart operation is in progress…"
    }

    /// Identity key WITHOUT a timestamp.
    private var detailKey: String {
        "\(details.entry.name)|\(details.entry.state)"
    }

    // MARK: Draft + validation
    // Pure TartKit functions; the view only renders their results. All
    // decisions and enforcement live in AppModel.apply.

    private var fields: ResourceEditorFields {
        ResourceEditorFields(cpuText: cpuText,
                             memoryText: memoryMBText,
                             diskText: diskText,
                             displayText: displayText,
                             displayRefit: refitOverride)
    }

    private var validation: VMResourceValidation {
        VMResourceValidator.validate(fields: fields,
                                     currentDiskGB: details.entry.diskSize,
                                     host: host)
    }

    private var editor: some View {
        Group {
            LabeledContent("CPUs") { TextField("4", text: editBinding($cpuText)).frame(width: 90) }
            LabeledContent("Memory (MB)") { TextField("8192", text: editBinding($memoryMBText)).frame(width: 120) }
            LabeledContent("Disk size (GB)") { TextField("80", text: editBinding($diskText)).frame(width: 90) }
            LabeledContent("Display") { TextField("1200x800", text: editBinding($displayText)).frame(width: 140) }
            Toggle("Automatically fit display to window", isOn: refitBinding)
            if !validation.warnings.isEmpty {
                ForEach(validation.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if !validation.errors.isEmpty {
                ForEach(validation.errors, id: \.self) { error in
                    Label(error, systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            HStack {
                Button("Apply") {
                    let snapshot = fields
                    let entry = details.entry
                    Task { await model.apply(fields: snapshot, to: entry, host: host) }
                }
                .disabled(!validation.isValid || fields.isEmpty)
                .buttonStyle(.borderedProminent)
                Button("Revert") {
                    // Force-populate: bypasses the loadedFor guard by
                    // clearing dirty and writing the live config directly.
                    isDirty = false
                    populate()
                }
                .disabled(!isDirty)
            }
        }
    }

    // MARK: Bindings (only user edits set the dirty flag)

    private func editBinding(_ binding: Binding<String>) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                isDirty = true
                binding.wrappedValue = newValue
            })
    }

    private var refitBinding: Binding<Bool> {
        Binding(
            get: { refitOverride ?? false },
            set: { newValue in
                isDirty = true
                refitOverride = newValue
            })
    }

    // MARK: Population

    private func load() {
        guard loadedFor != detailKey else { return }
        loadedFor = detailKey
        isDirty = false
        populate()
    }

    private func populate() {
        cpuText = details.config?.cpuCount.map(String.init) ?? ""
        // tart get reports memory in MB, so no conversion is needed.
        memoryMBText = details.config?.memoryMB.map(String.init) ?? ""
        // Whole-GB display: tart's --disk-size is whole GB, and the validator
        // compares against this same rounding — the shown value is always
        // re-applyable (79.4 GB displays and validates as 79).
        diskText = String(Int(details.entry.diskSize.rounded()))
        // tart get's Display is already a string ("1200x800" with optional
        // pt/px units), copied verbatim.
        displayText = details.config?.displayText ?? ""
        refitOverride = nil
    }

    /// tart only randomizes serials on Darwin guests; when the guest OS is
    /// unknown, the button stays enabled (default tart behavior).
    private var serialRegenerationAvailable: Bool {
        guard let os = details.config?.os else { return true }
        return os.lowercased() == "darwin"
    }
}
