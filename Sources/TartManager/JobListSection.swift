import SwiftUI
import TartKit

/// The "JOBS" section pinned to the bottom of the sidebar, above the status
/// bar. It observes `JobManager` directly so it re-renders on every job
/// mutation regardless of inventory polls (finding 1). It shows nothing
/// while no running or failed job exists, and it collapses to
/// `JobListPresentation.collapsedLimit` rows. A chevron beside the section
/// title expands and collapses the list, which grows upward.
struct JobListSection<Header: View>: View {
    @ObservedObject var jobManager: JobManager
    @ViewBuilder var header: () -> Header
    @State private var isExpanded = false

    var body: some View {
        let presentation = JobListPresentation(jobs: jobManager.jobs, isExpanded: isExpanded)
        if !presentation.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Rectangle().fill(WorkspaceStyle.line).frame(height: 1).padding(.horizontal, 10)
                HStack(spacing: 0) {
                    header()
                    Spacer(minLength: 0)
                    if let label = presentation.toggleLabel, let symbol = presentation.toggleSymbol {
                        toggle(label: label, symbol: symbol)
                    }
                }
                ForEach(presentation.visibleJobs) { job in
                    JobRowView(jobManager: jobManager, jobID: job.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    private func toggle(label: String, symbol: String) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WorkspaceStyle.muted)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .padding(.trailing, 10).padding(.top, 5)
    }
}
