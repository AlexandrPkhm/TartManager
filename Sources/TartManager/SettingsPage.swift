import SwiftUI

/// Settings use the same opaque surfaces as the workspace, avoiding the
/// native grouped Form's appearance- and window-focus-dependent materials.
struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content()
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(WorkspaceStyle.background)
        .foregroundStyle(WorkspaceStyle.text)
        .tint(WorkspaceStyle.accent)
        .labeledContentStyle(SettingsRowStyle())
    }
}

private struct SettingsRowStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label
            Spacer(minLength: 0)
            configuration.content
        }
    }
}

struct SettingsPanel<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.headline).padding(.horizontal, 10)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .workspacePanel()
        }
    }
}
