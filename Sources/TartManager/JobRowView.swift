import SwiftUI
import Combine
import TartKit

struct JobRowView: View {
    @ObservedObject var jobManager: JobManager
    @EnvironmentObject var model: AppModel
    let jobID: UUID

    /// Live lookup: the row re-renders on every `jobs` mutation, so it
    /// always shows current job state (never a stale value-copy, finding 1).
    private var job: JobInfo? {
        jobManager.jobs.first { $0.id == jobID }
    }

    @State private var now = Date()

    /// 1 Hz while running only: terminal rows receive no timer at all
    /// (finding 14). Stable publisher instances avoid resubscription churn.
    private let runningTicker = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()
        .eraseToAnyPublisher()
    private let idleTicker = Empty<Date, Never>().eraseToAnyPublisher()

    private var ticker: AnyPublisher<Date, Never> {
        job?.phase == .running ? runningTicker : idleTicker
    }

    var body: some View {
        if let job {
            HStack {
                phaseIcon(job)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(job))
                    detail(job)
                    if job.phase == .completed, let summary = job.summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer()
                actions(job)
            }
            .padding(.vertical, 2)
            .onReceive(ticker) { _ in now = Date() }
        }
    }

    private func phaseIcon(_ job: JobInfo) -> some View {
        Group {
            if job.phase == .running {
                ProgressView().controlSize(.small)
            } else if job.phase == .failed {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            } else if job.phase == .cancelled {
                Image(systemName: "xmark.circle").foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func detail(_ job: JobInfo) -> some View {
        switch job.phase {
        case .running:
            if let fraction = job.progress?.fraction {
                ProgressView(value: fraction)
                Text("\(Int(fraction * 100))%\(job.progress?.note.map { " · \($0)" } ?? "") · \(elapsed(job))s")
            } else {
                // Indeterminate jobs (local clones: instant CoW on APFS,
                // silent full copies on exFAT) show the note plus elapsed
                // seconds — matching Task 8 Step 1's expectation (finding 9).
                Text("\(job.progress?.note ?? "preparing…") · \(elapsed(job))s")
            }
        case .failed:
            if let error = job.error {
                Text(error.message).foregroundStyle(.red).lineLimit(2)
            }
        case .completed:
            Text(job.progress?.note ?? "done")
        case .cancelled:
            Text("cancelled")
        }
    }

    @ViewBuilder
    private func actions(_ job: JobInfo) -> some View {
        if job.phase == .running {
            // Restore jobs are not cancellable — no Cancel affordance is
            // rendered for them.
            if job.kind.isCancellable {
                Button {
                    jobManager.cancel(id: job.id)
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button("Details") { if let error = job.error { model.present(error) } }
                .buttonStyle(.borderless)
                .opacity(job.error == nil ? 0 : 1)
            Button {
                jobManager.dismiss(id: job.id)
            } label: {
                Label("Dismiss", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private func elapsed(_ job: JobInfo) -> Int {
        max(0, Int(now.timeIntervalSince(job.createdAt)))
    }

    private func title(_ job: JobInfo) -> String {
        switch job.kind {
        case .clone(let name, let source):
            return "Creating “\(name)” from \(shortSource(source))"
        case .importArchive(let name, let path):
            return "Importing “\(name)” from \((path as NSString).lastPathComponent)"
        case .exportSnapshot(let name):
            return "Snapshotting “\(name)”"
        case .restoreSnapshot(let name):
            return "Restoring “\(name)” from a snapshot"
        case .createFromIPSW(let name):
            return "Installing “\(name)” from an IPSW"
        case .deleteVM(let name):
            return "Deleting “\(name)”"
        case .replaceDisk(let name, let path):
            return "Replacing the disk of “\(name)”"
        case .prune:
            return "Pruning caches"
        }
    }

    private func shortSource(_ source: String) -> String {
        source.hasPrefix("ghcr.io/cirruslabs/")
            ? String(source.dropFirst("ghcr.io/cirruslabs/".count))
            : source
    }
}
