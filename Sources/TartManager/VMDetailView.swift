import SwiftUI
import TartKit

struct VMDetailView: View {
    @EnvironmentObject var model: AppModel
    let details: VMDetails
    @State private var snapshotSheetTarget: VMEntry?

    var body: some View {
        Form {
            LabeledContent("Name") { Text(details.entry.name).textSelection(.enabled) }
            LabeledContent("State") {
                Label(details.entry.state,
                      systemImage: details.entry.running ? "circle.fill" : "circle.slash")
                    .foregroundStyle(details.entry.running ? .green : .secondary)
            }
            LabeledContent("Source") {
                Text(details.entry.isLocal ? "local VM" : "OCI image")
            }
            LabeledContent("Disk") {
                Text("Allocated \(gigabytes(details.entry.diskSize)) GB · on disk \(gigabytes(details.entry.diskUsage)) GB")
            }
            if let accessed = details.entry.accessed {
                LabeledContent("Last accessed") {
                    Text(accessed.formatted(date: .abbreviated, time: .shortened))
                }
            }
            // Only local VMs have a config.json; OCI rows show no Configuration
            // section claiming values.
            if details.entry.isLocal {
                Section("Configuration") {
                    LabeledContent("CPUs") {
                        Text(details.config?.cpuCount.map(String.init) ?? "—")
                    }
                    LabeledContent("Memory") {
                        Text(details.config?.memoryMB.map { megabytes in
                            // tart get reports MB; the formatter expects bytes (Int64).
                            ByteCountFormatter.string(
                                fromByteCount: Int64(megabytes) * 1024 * 1024,
                                countStyle: .memory)
                        } ?? "—")
                    }
                    LabeledContent("Display") {
                        Text(details.config?.displayText ?? "—")
                    }
                }
            }
            if details.entry.isLocal {
                Section("Network") {
                    if details.entry.running {
                        LabeledContent("Guest IP") {
                            if let ip = details.ip {
                                Text(ip).textSelection(.enabled)
                            } else {
                                Text("resolving…").foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Connect") {
                            HStack {
                                Text(sshText).font(.system(.callout, design: .monospaced))
                                // Shared clipboard affordance (CopyButton); disabled
                                // until an IP exists so no empty command is copied.
                                CopyButton(value: sshText).disabled(details.ip == nil)
                            }
                        }
                    } else {
                        LabeledContent("Guest IP") { Text("— (VM is stopped)") }
                    }
                }
            }
            if details.entry.isLocal {
                Section("Snapshots") {
                    if details.entry.running {
                        Label("Stop the VM to take or restore snapshots.", systemImage: "pause.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await model.stop(vm: details.entry) }
                        } label: {
                            Label("Stop VM", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Stop this VM now (graceful shutdown)")
                    } else {
                        Button("Take Snapshot…") {
                            snapshotSheetTarget = details.entry
                        }
                    }
                    ForEach(model.vmSnapshots) { snapshot in
                        SnapshotRowView(snapshot: snapshot, entry: details.entry)
                    }
                }
                .sheet(item: Binding(
                    get: { model.pendingRestore },
                    set: { if $0 == nil { model.pendingRestore = nil } })) { pending in
                    RestoreSnapshotView(pending: pending).environmentObject(model)
                }
            }
            if details.entry.isLocal {
                VMDetailSharedFoldersSection(details: details)
            }
            if details.entry.isLocal {
                VMDetailSettingsSection(details: details, host: .current())
            }
        }
        .formStyle(.grouped)
        .navigationTitle(details.entry.name)
        .sheet(item: $snapshotSheetTarget) { vm in
            SnapshotCreateView(vm: vm).environmentObject(model)
        }
    }

    private var sshText: String {
        SSHCommand.text(user: model.settings.sshUser, ip: details.ip ?? "")
    }

    /// Unit-neutral row values rendered as GB, matching VMRowView's convention
    /// (unit formatting lives in the view, not the model).
    private func gigabytes(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
