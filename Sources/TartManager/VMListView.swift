import SwiftUI
import TartKit

struct VMListView: View {
    @ObservedObject var inventoryService: InventoryService
    @Binding var selection: VMEntry?
    @Binding var page: WorkspacePage
    @EnvironmentObject var model: AppModel
    var onCreateVM: () -> Void

    init(inventoryService: InventoryService,
         selection: Binding<VMEntry?>,
         page: Binding<WorkspacePage>,
         onCreateVM: @escaping () -> Void) {
        self.inventoryService = inventoryService
        self._selection = selection
        self._page = page
        self.onCreateVM = onCreateVM
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    sectionLabel("LIBRARY")
                    navigationRow("Virtual machines", symbol: "square.3.layers.3d",
                                  count: inventoryService.inventory?.localVMs.count ?? 0, target: .machines)
                    navigationRow("Images", symbol: "shippingbox",
                                  count: inventoryService.inventory?.ociImages.count ?? 0, target: .images)
                    sectionLabel("ON THIS MAC")
                    ForEach(inventoryService.inventory?.localVMs ?? []) { entry in
                        Button {
                            selection = entry
                            page = .machines
                        } label: {
                            VMRowView(entry: entry)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(page == .machines && selection?.id == entry.id
                                            ? WorkspaceStyle.selected : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(page == .machines && selection?.id == entry.id ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 12).padding(.top, 17)
            }
            // Pinned above the status bar, so the section grows upward as
            // jobs start or the list expands.
            JobListSection(jobManager: model.jobManager) {
                sectionLabel(JobRowCopy.sectionTitle)
            }
            .padding(.horizontal, 12)
            engineStatus.padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 15)
        }
        .background(WorkspaceStyle.sidebar)
        .confirmationDialog(
            "Stop “\(model.pendingForceStop?.name ?? "")” immediately?",
            isPresented: Binding(
                get: { model.pendingForceStop != nil },
                set: { if !$0 { model.pendingForceStop = nil } }),
            titleVisibility: .visible) {
                Button("Stop Immediately", role: .destructive) {
                    if let entry = model.pendingForceStop {
                        Task { await model.stop(vm: entry, force: true) }
                    }
                    model.pendingForceStop = nil
                }
                Button("Cancel", role: .cancel) { model.pendingForceStop = nil }
            } message: {
                Text("The guest gets no chance to save unsaved work.")
            }
        .sheet(item: cloneSheetBinding) { source in
            CloneVMView(source: source).environmentObject(model)
        }
        .alert("First run of an IPSW-created VM",
               isPresented: firstRunAlertBinding,
               presenting: model.firstRunVM) { vm in
            Button("Run VM") { model.confirmFirstRun() }
            Button("Cancel", role: .cancel) { model.firstRunVM = nil }
        } message: { vm in
            Text("The first boot of “\(vm.name)” opens macOS Setup Assistant — "
                 + "complete it inside the VM window.")
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.35)
            .foregroundStyle(WorkspaceStyle.muted)
            .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 5)
    }

    private func navigationRow(_ title: String, symbol: String, count: Int,
                               target: WorkspacePage) -> some View {
        Button { page = target } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 16)
                Text(title).font(.system(size: 12))
                Spacer(minLength: 0)
                Text(count, format: .number).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.muted)
            }
            .foregroundStyle(page == target ? WorkspaceStyle.accent : WorkspaceStyle.text)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(page == target ? WorkspaceStyle.selected : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(page == target ? .isSelected : [])
    }

    private var engineStatus: some View {
        HStack(spacing: 7) {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.iconOnly)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Settings")
            .help("Settings")
            Spacer(minLength: 0)
            Circle().fill(model.prerequisite?.isSatisfied == true ? WorkspaceStyle.green : .orange)
                .frame(width: 6, height: 6)
            Text(engineVersion)
        }
        .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.muted)
    }

    private var engineVersion: String {
        switch model.prerequisite {
        case .ok(let version, _): return "tart \(version)"
        case .outdated(let version, _, _): return "tart \(version) · outdated"
        case .missing: return "tart not found"
        case nil: return "Checking tart…"
        }
    }

    /// Item-driven clone sheet: presentation state lives in
    /// `model.cloningSource`; no local presentation `@State` exists
    /// (finding 6). `VMEntry` is `Identifiable` (Issue 3), so `sheet(item:)`
    /// works unchanged.
    private var cloneSheetBinding: Binding<VMEntry?> {
        Binding(
            get: { model.cloningSource },
            set: { if $0 == nil { model.cloningSource = nil } })
    }

    private var firstRunAlertBinding: Binding<Bool> {
        Binding(
            get: { model.firstRunVM != nil },
            set: { if !$0 { model.firstRunVM = nil } })
    }

    /// Friendly empty state with the "Create a VM" call to action, presented
    /// through the unified create sheet.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No VMs yet", systemImage: "desktopcomputer.and.arrow.down")
        } description: {
            Text("Clone an image or create a VM to begin.")
        } actions: {
            Button("Create a VM…") { onCreateVM() }
        }
    }
}
