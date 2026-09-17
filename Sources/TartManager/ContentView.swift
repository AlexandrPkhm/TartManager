import SwiftUI
import TartKit

struct ContentView: View {
    @State private var status: TartPrerequisiteStatus?
    @State private var isChecking = false
    private let checker = PrerequisiteChecker()

    var body: some View {
        VStack(spacing: 0) {
            if let status {
                if !status.isSatisfied, let info = TartPrerequisiteGuidance.guidance(for: status) {
                    PrerequisiteBanner(info: info, isChecking: isChecking) { recheck() }
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // Placeholder content region (VM list arrives in a later slice).
            ContentUnavailableView("No VMs yet",
                                  systemImage: "desktopcomputer.and.arrow.down",
                                  description: Text("Your tart VMs will appear here."))
                .frame(maxHeight: .infinity)
            Divider()
            statusFooter
        }
        .frame(minWidth: 640, minHeight: 420)
        .task {
            guard status == nil, !isChecking else { return }
            await runCheck()
        }
    }

    private var footerText: String {
        guard let status else { return "Checking for tart…" }
        switch status {
        case .ok(let version, _):
            return "tart \(version)"
        case .missing:
            return "tart not found"
        case .outdated(let found, let required, _):
            return "tart \(found) — needs \(required) or newer"
        }
    }

    private var statusFooter: some View {
        HStack {
            Spacer()
            Text(footerText).foregroundStyle(.secondary)
        }
        .padding(8)
    }

    private func recheck() {
        Task { await runCheck() }
    }

    /// Runs the (synchronous) check off the main actor: a wedged tart binary
    /// is bounded by ProcessRunner's timeout and never blocks the UI.
    private func runCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        status = await Task.detached(priority: .userInitiated) {
            checker.check()
        }.value
    }
}
