import SwiftUI
import TartKit

struct VMListView: View {
    @ObservedObject var inventoryService: InventoryService
    /// Observed directly so the Jobs section re-renders on every job
    /// mutation regardless of inventory polls (finding 1).
    @ObservedObject var jobManager: JobManager
    @Binding var selection: VMEntry?
    @EnvironmentObject var model: AppModel
    var onCreateVM: () -> Void

    init(inventoryService: InventoryService,
         jobManager: JobManager,
         selection: Binding<VMEntry?>,
         onCreateVM: @escaping () -> Void) {
        self.inventoryService = inventoryService
        self.jobManager = jobManager
        self._selection = selection
        self.onCreateVM = onCreateVM
    }

    var body: some View {
        List(selection: $selection) {
            if !jobManager.jobs.isEmpty {
                Section("Jobs") {
                    ForEach(jobManager.jobs) { job in
                        JobRowView(jobManager: jobManager, jobID: job.id)
                    }
                }
            }
            if let inventory = inventoryService.inventory {
                Section("Virtual Machines") {
                    ForEach(inventory.localVMs) { entry in
                        VMRowView(entry: entry).tag(Optional(entry))
                    }
                }
                if !inventory.ociImages.isEmpty {
                    Section("OCI Images") {
                        ForEach(inventory.ociImages) { entry in
                            VMRowView(entry: entry).tag(Optional(entry))
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
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
        .overlay {
            if let inventory = inventoryService.inventory,
               inventory.localVMs.isEmpty, inventory.ociImages.isEmpty {
                emptyState
            }
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
            Text("Clone a registry image or point Tart Manager at your tart storage in Settings.")
        } actions: {
            Button("Create a VM…") { onCreateVM() }
        }
    }
}
