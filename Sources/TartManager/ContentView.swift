import SwiftUI
import TartKit

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @State private var showingOnboarding = false
    @State private var showingCreate = false
    @State private var page: WorkspacePage = .machines
    @State private var importPath: String = ""
    @State private var importSuggestedName: String = ""
    @State private var titlebarHeight = WindowTitlebarConfiguration.defaultHeight

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
            titlebar
            WorkspaceStyle.line.frame(height: 1)
            if let status = model.prerequisite {
                if !status.isSatisfied, let info = TartPrerequisiteGuidance.guidance(for: status) {
                    PrerequisiteBanner(info: info, isChecking: model.isCheckingPrerequisite) {
                        model.checkPrerequisite()
                    }
                    Divider()
                }
            } else {
                ProgressView("Checking for tart…")
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            content
                .frame(maxHeight: .infinity)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 580)
        .background(WorkspaceStyle.background)
        .foregroundStyle(WorkspaceStyle.text)
        .tint(WorkspaceStyle.accent)
        .ignoresSafeArea(.container, edges: .top)
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
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            model.checkAutomaticPruning()
            model.refreshAvailability()
            Task { await model.inventoryService.refresh() }
        }
        .task {
            model.checkPrerequisite()
            model.startAutomaticPruning()
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
                NewVMSourceView()
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

    private var titlebar: some View {
        HStack(spacing: 9) {
            Text("Tart Manager").font(.system(size: 16, weight: .semibold)).tracking(-0.2)
            TitlebarUpdateButton()
            Spacer()
            Menu {
                AppearancePicker()
                    .pickerStyle(.inline)
                    .labelsHidden()
            } label: {
                Label("Appearance", systemImage: model.appearance.symbol)
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Appearance")
            .accessibilityValue(model.appearance.title)
            .help("Appearance: \(model.appearance.title)")
            Button { beginImport() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                .buttonStyle(WorkspaceButtonStyle(flat: true))
                .help("Import a .tvm archive")
            Button { showingCreate = true } label: { Label("New VM", systemImage: "plus") }
                .buttonStyle(WorkspaceButtonStyle())
                .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.leading, 94).padding(.trailing, 18).frame(height: titlebarHeight)
        .background(WorkspaceStyle.panel)
        .background(UnifiedTitlebar { height in
            if titlebarHeight != height { titlebarHeight = height }
        })
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
            HStack(spacing: 0) {
                VMListView(inventoryService: model.inventoryService,
                           selection: Binding(
                               get: { model.selectedVM },
                               set: { model.select($0) }),
                           page: $page,
                           onCreateVM: { showingCreate = true })
                    .frame(width: 219)
                WorkspaceStyle.line.frame(width: 1)
                Group {
                    if page == .images {
                        ImagesView(images: model.inventory?.ociImages ?? [])
                    } else if let entry = model.selectedVM {
                        VMDetailView(details: model.selectedDetails ?? VMDetails(
                            entry: entry, config: nil, ip: nil, fetchedAt: Date()))
                            .id(entry.id)
                    } else {
                        WorkspaceEmptyState(symbol: "desktopcomputer", title: "No virtual machines yet",
                                            message: "Clone an image or create a VM to begin.") {
                            Button { showingCreate = true } label: { Label("New VM", systemImage: "plus") }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            if let status = model.prerequisite {
                switch status {
                case .ok(let version, _):
                    Label {
                        Text(verbatim: "tart \(version)")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .foregroundStyle(.secondary)
                case .missing:
                    Label("tart not found", systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                case .outdated(let found, _, _):
                    Label {
                        Text(verbatim: "tart \(found) (outdated)")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.orange)
                }
            } else {
                Text("Checking for tart…").foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
