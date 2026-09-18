import SwiftUI
import TartKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingOnboarding = false
    @State private var showingCreate = false
    @State private var importPath: String = ""
    @State private var importSuggestedName: String = ""

    /// The one modal presented: onboarding while storage is unconfigured,
    /// otherwise the newest normalized failure, otherwise the create sheet,
    /// otherwise the import sheet (path picked). A published change to either
    /// source re-renders the body and the item binding presents the sheet.
    private var presentedSheet: RootSheet? {
        if showingOnboarding { return .onboarding }
        if let error = model.activeError { return .errorReport(error) }
        if showingCreate { return .createVM }
        if !importPath.isEmpty {
            return .importVM(path: importPath, suggestedName: importSuggestedName)
        }
        return nil
    }

    /// Item binding over `presentedSheet`: interactive dismissal (Esc) and
    /// the in-sheet `dismiss()`/Close both clear the underlying source, so
    /// the flags can never desync.
    private var sheetBinding: Binding<RootSheet?> {
        Binding(
            get: { presentedSheet },
            set: { newValue in
                if newValue == nil {
                    showingOnboarding = false
                    model.activeError = nil
                    showingCreate = false
                    importPath = ""
                }
            })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let status = model.prerequisite {
                if !status.isSatisfied, let info = TartPrerequisiteGuidance.guidance(for: status) {
                    PrerequisiteBanner(info: info, isChecking: model.isCheckingPrerequisite) {
                        model.checkPrerequisite()
                    }
                } else if case .ok(let version, _) = status {
                    Label("tart \(version)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.green.opacity(0.06))
                }
                Divider()
            } else {
                ProgressView("Checking for tart…")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            content
                .frame(maxHeight: .infinity)
            Divider()
            statusFooter
        }
        .frame(minWidth: 640, minHeight: 420)
        .confirmationDialog("This Mac may run out of memory",
                            isPresented: Binding(
                                get: { model.pendingRunWarning != nil },
                                set: { if !$0 { model.cancelWarningRun() } }),
                            titleVisibility: .visible) {
                Button("Run Anyway", role: .destructive) {
                    // Synchronous: captures the pending warning before the
                    // dialog dismissal clears it (see proceedWithWarningRun).
                    model.proceedWithWarningRun()
                }
                Button("Cancel", role: .cancel) { model.cancelWarningRun() }
            } message: {
                Text(model.pendingRunWarning?.assessment.summaryText
                     ?? "Combined VM memory approaches this Mac's RAM.")
            }
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.inventoryService.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh the VM list")
            }
            ToolbarItem {
                Button { showingCreate = true } label: {
                    Label("Create VM", systemImage: "plus")
                }
                .help("Create a VM from an image")
            }
            ToolbarItem {
                Button { beginImport() } label: {
                    Label("Import VM", systemImage: "square.and.arrow.down")
                }
                .help("Import a .tvm archive")
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.inventoryService.refresh() }
        }
        .task {
            model.checkPrerequisite()
            showingOnboarding = model.requiresOnboarding
            model.inventoryService.startPolling()
        }
        .onChange(of: model.requiresOnboarding) { _, requiresOnboarding in
            showingOnboarding = requiresOnboarding
        }
        .onChange(of: model.selectedVM) { _, _ in
            Task { await model.refreshSelectedDetails() }
        }
        .onChange(of: model.inventory) { _, _ in
            Task { await model.refreshSelectedDetails() }
        }
        .sheet(item: sheetBinding) { sheet in
            switch sheet {
            case .onboarding:
                OnboardingView()
                    .environmentObject(model)
                    .interactiveDismissDisabled()
            case .errorReport(let error):
                ErrorReportSheet(error: error) { model.activeError = nil }
            case .createVM:
                CreateVMView()
                    .environmentObject(model)
            case .importVM(let path, let suggestedName):
                ImportVMView(path: path, suggestedName: suggestedName)
                    .environmentObject(model)
            }
        }
        // The Delete/Rename sheets are owned here (single documented owner):
        // item-driven over the model's targets, matching the Clone sheet's
        // pattern — no local presentation state anywhere.
        .sheet(item: Binding(
            get: { model.renamingSource },
            set: { if $0 == nil { model.renamingSource = nil } })) { vm in
            RenameVMView(vm: vm).environmentObject(model)
        }
        .sheet(item: Binding(
            get: { model.deletingSource },
            set: { if $0 == nil { model.deletingSource = nil } })) { vm in
            DeleteVMView(vm: vm).environmentObject(model)
        }
        .sheet(item: Binding(
            get: { model.replacingDiskSource },
            set: { if $0 == nil { model.replacingDiskSource = nil } })) { vm in
            ReplaceDiskView(vm: vm).environmentObject(model)
        }
    }

    /// Runs the system file picker for `.tvm` archives; the flow stays
    /// file-path based until the sheet confirms and starts the job.
    private func beginImport() {
        guard let path = FilePicker.chooseFile(title: "Choose a .tvm archive",
                                              allowedExtensions: ["tvm"]) else { return }
        let suggested = ((path as NSString).lastPathComponent as NSString)
            .deletingPathExtension
        importPath = path
        importSuggestedName = suggested
    }

    @ViewBuilder private var content: some View {
        if model.requiresOnboarding {
            ContentUnavailableView("Welcome to Tart Manager",
                                  systemImage: "desktopcomputer.and.arrow.down",
                                  description: Text("Set up your VM storage to begin."))
        } else if !model.storageAvailability.isAvailable {
            StorageUnavailableView()
        } else if !prerequisiteSatisfied {
            ContentUnavailableView("tart required",
                                  systemImage: "terminal",
                                  description: Text("Install tart (see banner) to manage VMs."))
        } else {
            NavigationSplitView {
                VMListView(inventoryService: model.inventoryService,
                           jobManager: model.jobManager,
                           selection: Binding(
                               get: { model.selectedVM },
                               set: { model.select($0) }),
                           onCreateVM: { showingCreate = true })
                    .navigationSplitViewColumnWidth(min: 260, ideal: 320)
            } detail: {
                if let details = model.selectedDetails {
                    VMDetailView(details: details)
                } else {
                    ContentUnavailableView("Select a VM",
                                          systemImage: "sidebar.trailing",
                                          description: Text("Choose a VM to see its details."))
                }
            }
        }
    }

    private var prerequisiteSatisfied: Bool {
        model.prerequisite?.isSatisfied == true
    }

    // Maps each status explicitly (also fixes the previous footer, which
    // showed "tart not found" for the outdated case).
    private var statusFooter: some View {
        HStack {
            Spacer()
            if let status = model.prerequisite {
                switch status {
                case .ok(let version, _):
                    Text("tart \(version)").foregroundStyle(.secondary)
                case .missing:
                    Text("tart not found").foregroundStyle(.secondary)
                case .outdated(let found, _, _):
                    Text("tart \(found) (outdated)").foregroundStyle(.orange)
                }
            } else {
                Text("Checking for tart…").foregroundStyle(.secondary)
            }
        }
        .padding(8)
    }
}
