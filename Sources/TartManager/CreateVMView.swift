import SwiftUI
import TartKit

struct OCIPreset: Identifiable {
    let id = UUID()
    let label: String
    let reference: String
}

/// Clickable presets for the standard Cirrus Labs catalog (maintained list;
/// free-form entry is always available next to it).
let ociPresets: [OCIPreset] = [
    OCIPreset(label: "macOS Tahoe · base", reference: "ghcr.io/cirruslabs/macos-tahoe-base:latest"),
    OCIPreset(label: "macOS Tahoe · vanilla", reference: "ghcr.io/cirruslabs/macos-tahoe-vanilla:latest"),
    OCIPreset(label: "macOS Tahoe · Xcode", reference: "ghcr.io/cirruslabs/macos-tahoe-xcode:latest"),
    OCIPreset(label: "macOS Sequoia · base", reference: "ghcr.io/cirruslabs/macos-sequoia-base:latest"),
    OCIPreset(label: "macOS Sonoma · base", reference: "ghcr.io/cirruslabs/macos-sonoma-base:latest"),
]

enum CreateMode: Hashable {
    case image
    case ipsw
}

/// The create sheet with two sources. No business logic here: every gate is
/// a `model.` query and the Space section renders the model's assessment —
/// the view performs no arithmetic.
struct CreateVMView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: CreateMode = .image
    @State private var name = ""
    // Image mode
    @State private var reference = ""
    @State private var blockedReason: String?
    // IPSW mode
    @State private var useLatestIPSW = false
    @State private var ipswPath = ""
    @State private var diskSizeText = "50"
    @State private var confirmingLowSpace = false

    init(mode: CreateMode = .image, imageReference: String = "") {
        _mode = State(initialValue: mode)
        _reference = State(initialValue: imageReference)
    }

    var body: some View {
        Form {
            Section("New VM") {
                TextField("Name", text: $name)
                Picker("Source", selection: $mode) {
                    Text("Registry image").tag(CreateMode.image)
                    Text("IPSW file").tag(CreateMode.ipsw)
                }
                .pickerStyle(.segmented)
                if !name.isEmpty && !model.isNameAvailable(name) {
                    Label("A VM or image with this name already exists.", systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                if let blockedReason {
                    Label(blockedReason, systemImage: "xmark.octagon")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            switch mode {
            case .image:
                imageSection
            case .ipsw:
                ipswSection
            }
            Section("Space") {
                LabeledContent("Free space in storage") {
                    Text(freeBytesText)
                }
                LabeledContent("Estimated need") {
                    Text(estimateText)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 440)
        .onAppear { model.invalidateStorageProbeCache() }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(mode == .image ? "Download & Create" : "Install from IPSW") { start() }
                    .disabled(!canStart)
                    .buttonStyle(WorkspaceButtonStyle(primary: true)).keyboardShortcut(.defaultAction)
            }.padding(20)
        }
        .confirmationDialog("Low disk space",
                            isPresented: $confirmingLowSpace,
                            titleVisibility: .visible) {
            Button(mode == .image ? "Download Anyway" : "Install Anyway") {
                startIgnoringSpaceWarning()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Free space is nearly exhausted; the operation may fail part-way.")
        }
    }

    private var imageSection: some View {
        Section("Image") {
            TextField("Image reference (host/repo:tag)", text: $reference)
            Menu("Quick picks (Cirrus Labs)") {
                ForEach(ociPresets) { preset in
                    Button(preset.label) { reference = preset.reference }
                }
            }
        }
    }

    private var ipswSection: some View {
        Section("Restore image") {
            Toggle("Use latest supported IPSW", isOn: $useLatestIPSW)
            if !useLatestIPSW {
                HStack {
                    Text(ipswPath.isEmpty
                         ? "No file chosen"
                         : (ipswPath as NSString).lastPathComponent)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") {
                        if let path = FilePicker.chooseFile(
                            title: "Choose an IPSW restore image",
                            allowedExtensions: ["ipsw"]) {
                            ipswPath = path
                        }
                    }
                }
            }
            TextField("Disk size (GB)", text: $diskSizeText)
            if let diskSizeError {
                Label(diskSizeError, systemImage: "xmark.octagon")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            Label("The first run of a fresh IPSW VM requires completing "
                  + "macOS Setup Assistant inside the VM window.",
                  systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The disk size must parse to a positive, bounded whole GB — invalid
    /// text shows an inline error and disables Start; there is no fallback
    /// default.
    private var diskSizeError: String? {
        guard !diskSizeText.isEmpty, !IPSWCreateRules.isValidDiskSizeText(diskSizeText) else {
            return nil
        }
        return "Enter a whole number of gigabytes between 1 and \(IPSWCreateRules.maxDiskSizeGB)."
    }

    private var canStart: Bool {
        guard !name.isEmpty else { return false }
        switch mode {
        case .image:
            return !reference.isEmpty
                && model.createBlockReason(name: name, reference: reference) == nil
        case .ipsw:
            guard useLatestIPSW || !ipswPath.isEmpty,
                  let diskSizeGB = IPSWCreateRules.parseDiskSizeGB(diskSizeText) else {
                return false
            }
            return model.createFromIPSWBlockReason(name: name, diskSizeGB: diskSizeGB) == nil
        }
    }

    private var freeBytesText: String {
        guard let free = model.storageFreeBytes else { return "unknown" }
        return ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
    }

    private var estimateText: String {
        switch mode {
        case .image:
            return "~80 GB (macOS base image, conservative)"
        case .ipsw:
            let assessment = model.createIPSWPreflight(
                usesLatest: useLatestIPSW, ipswPath: ipswPath, diskSizeText: diskSizeText)
            guard let estimate = assessment.estimateBytes else { return "unknown" }
            return "~" + ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file)
        }
    }

    private var spaceVerdict: DiskSpacePolicy.Verdict? {
        switch mode {
        case .image:
            return model.createSpaceVerdict()
        case .ipsw:
            return model.createIPSWPreflight(
                usesLatest: useLatestIPSW, ipswPath: ipswPath, diskSizeText: diskSizeText)
                .verdict
        }
    }

    private func start() {
        guard canStart else { return }
        if let verdict = spaceVerdict, verdict.isTight {
            confirmingLowSpace = true
        } else {
            startIgnoringSpaceWarning()
        }
    }

    private func startIgnoringSpaceWarning() {
        switch mode {
        case .image:
            if let reason = model.startCreate(name: name, reference: reference) {
                blockedReason = reason
            } else {
                dismiss()
            }
        case .ipsw:
            guard let diskSizeGB = IPSWCreateRules.parseDiskSizeGB(diskSizeText) else { return }
            blockedReason = nil
            if model.startCreateFromIPSW(
                name: name,
                ipsw: useLatestIPSW ? "latest" : ipswPath,
                diskSizeGB: diskSizeGB) != nil {
                dismiss()
            }
        }
    }
}
