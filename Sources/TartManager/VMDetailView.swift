import SwiftUI
import TartKit

struct VMDetailView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var stopCoordinator: StopCoordinator
    @EnvironmentObject var suspendCoordinator: SuspendCoordinator
    let details: VMDetails
    @State private var snapshotSheetTarget: VMEntry?
    @State private var selectedTab: VMDetailTab = .overview
    @State private var editingResources = false
    @State private var requestingAction = false
    @State private var requestingSuspend = false
    @State private var hoveringSuspend = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("VIRTUAL MACHINE").font(.system(size: 11)).tracking(0.7)
                    .foregroundStyle(WorkspaceStyle.muted).padding(.bottom, 22)
                header.padding(.bottom, 27)
                tabs.padding(.bottom, 23)
                // Preserve in-progress folder edits when switching tabs.
                overview.frame(height: selectedTab == .overview ? nil : 0)
                    .clipped().opacity(selectedTab == .overview ? 1 : 0)
                    .allowsHitTesting(selectedTab == .overview).accessibilityHidden(selectedTab != .overview)
                snapshots.frame(height: selectedTab == .snapshots ? nil : 0)
                    .clipped().opacity(selectedTab == .snapshots ? 1 : 0)
                    .allowsHitTesting(selectedTab == .snapshots).accessibilityHidden(selectedTab != .snapshots)
                VMDetailSharedFoldersSection(details: details)
                    .frame(height: selectedTab == .sharedFolders ? nil : 0)
                    .clipped().opacity(selectedTab == .sharedFolders ? 1 : 0)
                    .allowsHitTesting(selectedTab == .sharedFolders).accessibilityHidden(selectedTab != .sharedFolders)
            }
            .padding(.horizontal, 32).padding(.top, 29).padding(.bottom, 22)
        }
        .sheet(isPresented: $editingResources) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Edit resources").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Button("Done") { editingResources = false }.keyboardShortcut(.cancelAction)
                }.padding(24)
                Form { VMDetailSettingsSection(details: details, host: .current()) }
                    .formStyle(.grouped)
            }.frame(width: 520, height: 510)
        }
        .sheet(item: $snapshotSheetTarget) { vm in
            SnapshotCreateView(vm: vm).environmentObject(model)
        }
        .sheet(item: Binding(get: { model.pendingRestore },
                             set: { if $0 == nil { model.pendingRestore = nil } })) { pending in
            RestoreSnapshotView(pending: pending).environmentObject(model)
        }
    }

    private var header: some View {
        HStack(spacing: 17) {
            Image(systemName: "desktopcomputer").font(.system(size: 30, weight: .light))
                .foregroundStyle(WorkspaceStyle.accent).frame(width: 62, height: 62)
                .background(WorkspaceStyle.selected, in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 7) {
                Text(details.entry.name).font(.system(size: 22, weight: .semibold)).tracking(-0.6)
                    .lineLimit(1).truncationMode(.middle).help(details.entry.name)
                HStack(spacing: 6) {
                    Circle().fill(details.entry.running ? WorkspaceStyle.green : WorkspaceStyle.muted)
                        .frame(width: 6, height: 6)
                    Text(details.entry.state.capitalized)
                        .foregroundStyle(details.entry.running ? WorkspaceStyle.green : WorkspaceStyle.muted)
                    if let os = details.config?.os {
                        Text("·  \(os.lowercased() == "darwin" ? "macOS" : os.capitalized)")
                            .foregroundStyle(WorkspaceStyle.muted)
                    }
                }.font(.system(size: 12))
            }
            Spacer(minLength: 12)
            if details.entry.canSuspend || isSuspending {
                Button {
                    let vm = details.entry
                    requestingSuspend = true
                    Task {
                        await model.suspend(vm: vm)
                        requestingSuspend = false
                    }
                } label: {
                    HStack(spacing: 7) {
                        if isSuspending { ProgressView().controlSize(.mini) }
                        else { Image(systemName: "pause.fill") }
                        Text(isSuspending ? "Suspending…" : "Suspend")
                    }
                }
                .buttonStyle(WorkspaceButtonStyle(flat: true))
                .background(hoveringSuspend && !isBusy ? WorkspaceStyle.line.opacity(0.5) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .onHover { hoveringSuspend = $0 }
                .disabled(isBusy)
                .help("Suspend this VM and keep its session for later")
                .accessibilityIdentifier("suspendVM")
            }
            Button {
                requestingAction = true
                Task {
                    if details.entry.running { await model.stop(vm: details.entry) }
                    else { await model.requestRun(vm: details.entry) }
                    requestingAction = false
                }
            } label: {
                HStack(spacing: 7) {
                    if requestingAction || stopCoordinator.stopping.contains(details.entry.name) {
                        ProgressView().controlSize(.mini)
                    }
                    else { Image(systemName: details.entry.running ? "stop.fill" : "play.fill") }
                    Text(actionTitle)
                }
            }.buttonStyle(WorkspaceButtonStyle(primary: !details.entry.running)).disabled(isBusy)
        }
    }

    private var isBusy: Bool {
        requestingAction || stopCoordinator.stopping.contains(details.entry.name)
            || isSuspending
    }
    private var isSuspending: Bool {
        requestingSuspend || suspendCoordinator.suspending.contains(details.entry.name)
    }
    private var actionTitle: String {
        if stopCoordinator.stopping.contains(details.entry.name) { return "Stopping…" }
        return details.entry.running ? "Stop" : details.entry.primaryActionLabel(
            distinguishesSuspended: SuspendedStateReporting.distinguishesSuspended)
    }

    private var tabs: some View {
        HStack(spacing: 22) {
            ForEach(VMDetailTab.allCases) { tab in
                Button { selectedTab = tab } label: {
                    Text(tab.rawValue == "Shared Folders" ? "Shared folders" : tab.rawValue)
                        .font(.system(size: 12, weight: selectedTab == tab ? .medium : .regular))
                        .foregroundStyle(selectedTab == tab ? WorkspaceStyle.accent : WorkspaceStyle.muted)
                        .padding(.bottom, 11)
                        .overlay(alignment: .bottom) {
                            if selectedTab == tab { WorkspaceStyle.accent.frame(height: 2) }
                        }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }.background(alignment: .bottom) { WorkspaceStyle.line.frame(height: 1) }
            .accessibilityElement(children: .contain).accessibilityLabel("VM details tabs")
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                resourceMetric("CPU", value: details.config?.cpuCount.map(String.init) ?? "—", unit: "cores", symbol: "cpu")
                resourceMetric("Memory", value: memoryValue, unit: "GB", symbol: "memorychip")
                resourceMetric("Disk", value: number(details.entry.diskSize), unit: "GB", symbol: "internaldrive")
            }.padding(.bottom, 25)
            HStack {
                Text("Configuration").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Edit resources…") { editingResources = true }
                    .buttonStyle(.plain).foregroundStyle(WorkspaceStyle.accent).font(.system(size: 12))
                    .disabled(!details.entry.canEditResources || model.applyingResources)
                    .help(details.entry.canEditResources ? "Edit CPU, memory, disk and display" : "Stop the VM to edit resources")
            }.padding(.bottom, 10)
            VStack(spacing: 0) {
                configurationRow("Architecture", value: architecture)
                WorkspaceStyle.line.frame(height: 1)
                configurationRow("Storage location", value: storageLocation)
                WorkspaceStyle.line.frame(height: 1)
                configurationRow("Network", value: details.entry.running
                                 ? details.ip ?? "Resolving address…" : "Available when running")
                    .contextMenu {
                        Button("Copy SSH command") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(SSHCommand.text(user: model.settings.sshUser,
                                                                         ip: details.ip ?? ""), forType: .string)
                        }.disabled(details.ip == nil)
                    }
            }.padding(.horizontal, 15).workspacePanel()
            Label(details.entry.canEditResources
                  ? "Ready to start. Resources are allocated when running."
                  : "Stop the virtual machine to edit its resources.", systemImage: "info.circle")
                .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.muted).padding(.top, 18)
        }
    }

    private var snapshots: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.vmSnapshots.isEmpty {
                WorkspaceEmptyState(symbol: "clock.arrow.circlepath", title: "No snapshots yet",
                                    message: "Save a restore point before making changes.") {
                    Button { snapshotSheetTarget = details.entry } label: {
                        Label("Create snapshot", systemImage: "plus")
                    }.disabled(details.entry.running)
                }
            } else {
                HStack {
                    Text("Snapshots").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button { snapshotSheetTarget = details.entry } label: {
                        Label("Create snapshot", systemImage: "plus")
                    }.buttonStyle(WorkspaceButtonStyle()).disabled(details.entry.running)
                }
                VStack(spacing: 12) {
                    ForEach(model.vmSnapshots) { snapshot in
                        SnapshotRowView(snapshot: snapshot, entry: details.entry)
                    }
                }.padding(15).workspacePanel()
            }
            if details.entry.running {
                Label("Stop the VM to take or restore snapshots.", systemImage: "info.circle")
                    .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.muted)
            }
        }
    }

    private func configurationRow(_ title: String, value: String) -> some View {
        HStack(spacing: 15) {
            Text(title)
            Spacer(minLength: 0)
            Text(value).foregroundStyle(WorkspaceStyle.muted).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled).help(value)
        }.font(.system(size: 12)).frame(minHeight: 40)
    }
    private func resourceMetric(_ title: String, value: String, unit: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol).font(.system(size: 11)).foregroundStyle(WorkspaceStyle.muted)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: 23, weight: .medium)).tracking(-0.6).monospacedDigit()
                Text(unit).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(15).workspacePanel()
    }
    private var memoryValue: String {
        details.config?.memoryMB.map { number(Double($0) / 1024) } ?? "—"
    }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private var architecture: String {
        #if arch(arm64)
        return "Apple silicon · arm64"
        #else
        return "Intel · x86_64"
        #endif
    }
    private var storageLocation: String {
        guard let path = model.settings.storagePath else { return "Not configured" }
        return "Local · \((path as NSString).abbreviatingWithTildeInPath)"
    }
}
