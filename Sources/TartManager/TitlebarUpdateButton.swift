import SwiftUI
import TartKit

/// The main-window title-bar button for an available or waiting update. It
/// renders nothing for every other status.
struct TitlebarUpdateButton: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let label = UpdateStatusCopy(status: model.updateStatus).titlebarLabel {
            Button {
                activate()
            } label: {
                Label(label, systemImage: "arrow.down.circle")
                    .foregroundStyle(WorkspaceStyle.accent)
            }
            .buttonStyle(WorkspaceButtonStyle(flat: true))
            .accessibilityLabel(label)
            .help(label)
        }
    }

    /// `.available` and a failure with a known version open Sparkle's update
    /// window. `.waitingForJobs` opens Settings → About, which shows the full
    /// status line.
    private func activate() {
        if case .waitingForJobs = model.updateStatus {
            model.showAbout()
            openSettings()
        } else {
            model.checkForUpdates()
        }
    }
}
