import SwiftUI
import Combine
import TartKit

/// One job in the sidebar "JOBS" section. The section lists only running
/// and failed jobs (`JobRetentionPolicy.isListed`).
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
            let copy = JobRowCopy(job: job, now: now)
            HStack(alignment: .top, spacing: 8) {
                phaseIcon(job).frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.title)
                        .font(.system(size: 12))
                        .foregroundStyle(WorkspaceStyle.text)
                        .lineLimit(1).truncationMode(.tail)
                    caption(job, copy: copy)
                    if job.phase == .running, let fraction = job.progress?.fraction {
                        progressBar(fraction)
                    }
                }
                Spacer(minLength: 0)
                actions(job)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .help(copy.title)
            .onReceive(ticker) { now = $0 }
        }
    }

    @ViewBuilder
    private func phaseIcon(_ job: JobInfo) -> some View {
        switch job.phase {
        case .running:
            ProgressView().controlSize(.mini)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.warning)
        case .completed, .cancelled:
            EmptyView()   // not listed
        }
    }

    @ViewBuilder
    private func caption(_ job: JobInfo, copy: JobRowCopy) -> some View {
        HStack(spacing: 6) {
            Text(copy.caption)
                .foregroundStyle(job.phase == .failed ? WorkspaceStyle.warning : WorkspaceStyle.muted)
                .lineLimit(1).truncationMode(.tail)
            if job.phase == .failed, let error = job.error {
                Button(JobRowCopy.detailsLabel) { model.present(error) }
                    .buttonStyle(.plain)
                    .foregroundStyle(WorkspaceStyle.accent)
            }
        }
        .font(.system(size: 11))
    }

    private func progressBar(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WorkspaceStyle.line)
                Capsule().fill(WorkspaceStyle.accent)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 3)
    }

    @ViewBuilder
    private func actions(_ job: JobInfo) -> some View {
        switch job.phase {
        case .running where job.kind.isCancellable:
            // Restore, delete, and replace-disk jobs are not cancellable:
            // no Cancel affordance is rendered for them.
            iconButton(JobRowCopy.cancelLabel) { jobManager.cancel(id: job.id) }
        case .failed:
            iconButton(JobRowCopy.dismissLabel) { jobManager.dismiss(id: job.id) }
        default:
            EmptyView()
        }
    }

    private func iconButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WorkspaceStyle.muted)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
