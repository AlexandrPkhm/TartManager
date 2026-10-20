import SwiftUI
import TartKit

/// Settings → About: the app identity, the update status, and links to the
/// project. It replaces the long About sheet; the README holds the help
/// topics.
struct AboutSettingsView: View {
    @EnvironmentObject var model: AppModel

    static let description =
        "A native macOS control center for managing local tart virtual machines without the terminal."
    static let gitHubURL = URL(string: "https://github.com/AlexandrPkhm/TartManager")!
    static let documentationURL = URL(string: "https://github.com/AlexandrPkhm/TartManager#readme")!

    private var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Version \($0)" } ?? "Development build"
    }

    var body: some View {
        let copy = UpdateStatusCopy(status: model.updateStatus)
        SettingsPage {
            HStack(spacing: 12) {
                Image(nsImage: AppIcon.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tart Manager").font(.title2).bold()
                    Text(versionLine)
                        .foregroundStyle(WorkspaceStyle.muted)
                        .textSelection(.enabled)
                }
            }
            Text(Self.description)
                .foregroundStyle(WorkspaceStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            SettingsPanel(title: "Updates") {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.aboutLine)
                        if let lastCheck = model.lastUpdateCheck {
                            Text("Last checked: \(lastCheck.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(WorkspaceStyle.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Check for Updates") { model.checkForUpdates() }
                        .buttonStyle(WorkspaceButtonStyle())
                        .disabled(!copy.canCheck)
                        .accessibilityLabel("Check for Updates")
                }
            }
            HStack(spacing: 16) {
                Link("GitHub", destination: Self.gitHubURL)
                    .accessibilityLabel("Open Tart Manager on GitHub")
                Link("Documentation", destination: Self.documentationURL)
                    .accessibilityLabel("Open the Tart Manager documentation")
            }
            .foregroundStyle(WorkspaceStyle.accent)
        }
    }
}
