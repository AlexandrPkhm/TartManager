import SwiftUI
import TartKit

struct VMRowView: View {
    let entry: VMEntry
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var stopCoordinator: StopCoordinator
    @EnvironmentObject var suspendCoordinator: SuspendCoordinator

    var body: some View {
        HStack {
            Image(systemName: symbolName)
                .foregroundStyle(entry.isLocal && entry.running ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                Text(entry.isLocal ? entry.state : "registry image — clone to use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if entry.isLocal {
                // Unit formatting lives here, not in the model.
                Text("Disk \(Int(entry.diskSize)) GB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if suspendCoordinator.suspending.contains(entry.name) {
                    ProgressView()
                        .controlSize(.small)
                        .help("Suspending…")
                } else if stopCoordinator.stopping.contains(entry.name) {
                    ProgressView()
                        .controlSize(.small)
                        .help("Stopping…")
                } else if entry.running {
                    // The green dot stays as the running badge; the Suspend
                    // button joins the Stop button.
                    Image(systemName: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .help(entry.state)
                    Button {
                        Task { await model.suspend(vm: entry) }
                    } label: {
                        Label("Suspend", systemImage: "pause.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Suspend — the session resumes later via Resume")
                    Button {
                        Task { await model.stop(vm: entry) }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Stop this VM (graceful shutdown, forced after 30 s)")
                } else {
                    // Resume vs Run per the Task 1 mapping; the issue's
                    // fallback offers Resume on both.
                    let actionLabel = entry.primaryActionLabel(
                        distinguishesSuspended:
                            SuspendedStateReporting.distinguishesSuspended)
                    Button {
                        Task { await model.requestRun(vm: entry) }
                    } label: {
                        Label(actionLabel, systemImage: "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(actionLabel == "Resume"
                          ? "Resume the suspended session (boots the VM if it is stopped)"
                          : "Run this VM")
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            if entry.isLocal {
                if entry.running
                    && !suspendCoordinator.suspending.contains(entry.name)
                    && !stopCoordinator.stopping.contains(entry.name) {
                    Button("Suspend") {
                        Task { await model.suspend(vm: entry) }
                    }
                    Divider()
                    Button("Stop") {
                        Task { await model.stop(vm: entry) }
                    }
                    Divider()
                    Button("Force Stop…", role: .destructive) {
                        model.pendingForceStop = entry
                    }
                }
                if entry.running {
                    Divider()
                    // The requirement's explanation is the item's own visible
                    // title: macOS context menus render disabled items greyed
                    // but readable, and never show hover tooltips — so the
                    // explanation lives in the title, not in `.help()`
                    // (finding 1).
                    Button {
                        model.cloningSource = entry
                    } label: {
                        Text("Clone… — stop the VM first")
                    }
                    .disabled(true)
                    // Finding 1: the running-row requirement is the disabled
                    // item's own visible title (Issue 10's pattern).
                    Button { } label: {
                        Text("Replace Disk… — stop the VM first")
                    }
                    .disabled(true)
                } else {
                    Button("Clone…") {
                        model.cloningSource = entry
                    }
                    if entry.isStoppedLocal {
                        Divider()
                        Button("Rename…") {
                            model.renamingSource = entry
                        }
                        Divider()
                        // Finding 1: offered only for stopped (non-suspended)
                        // rows; suspended rows get the same disabled-explanatory
                        // title instead of a silently-no-oping action.
                        if entry.canReplaceDisk {
                            Button("Replace Disk…", role: .destructive) {
                                model.replacingDiskSource = entry
                            }
                        } else {
                            Button { } label: {
                                Text("Replace Disk… — resume and stop the VM first")
                            }
                            .disabled(true)
                        }
                        Divider()
                        Button("Delete…", role: .destructive) {
                            model.deletingSource = entry
                        }
                    } else {
                        // Suspended (or otherwise not stopped): Delete/Rename
                        // are gated per US 19/20 AC2 — the explanation is the
                        // disabled item's own visible title.
                        Button("Rename/Delete — stop the VM first") {}
                            .disabled(true)
                        // Finding 1: a suspended row can never reach the
                        // replace path — the explanation is the disabled
                        // item's own visible title.
                        Button { } label: {
                            Text("Replace Disk… — resume and stop the VM first")
                        }
                        .disabled(true)
                    }
                }
            }
        }
    }

    private var symbolName: String {
        if entry.isLocal {
            return entry.running ? "play.desktopcomputer" : "desktopcomputer"
        }
        return "shippingbox"
    }
}
