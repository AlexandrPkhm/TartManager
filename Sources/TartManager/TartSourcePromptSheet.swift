import SwiftUI
import TartKit

/// The one-time sheet that asks an upgrading user, who has a working
/// installed tart, which tart to use. It has no close button: only an
/// answer stores a source. Until then the installed tart stays active.
struct TartSourcePromptSheet: View {
    @EnvironmentObject var model: AppModel
    let report: TartRuntimeReport

    var body: some View {
        let copy = TartSourcePromptCopy(report: report)
        VStack(alignment: .leading, spacing: 16) {
            Text(copy.title).font(.headline)
            Text(copy.body)
                .foregroundStyle(WorkspaceStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text(copy.bundledLabel)
                    Text(verbatim: copy.bundledDetail).foregroundStyle(WorkspaceStyle.muted)
                    Text(verbatim: "")
                }
                GridRow {
                    Text(copy.installedLabel)
                    Text(verbatim: copy.installedDetail).foregroundStyle(WorkspaceStyle.muted)
                    Text(verbatim: copy.installedPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(WorkspaceStyle.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(copy.installedPath)
                }
            }
            if let warning = copy.warning {
                Label {
                    Text(warning).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(WorkspaceStyle.warning)
            }
            HStack {
                Spacer()
                Button(copy.keepInstalledButton) { model.answerTartSourcePrompt(.installed) }
                Button(copy.useBundledButton) { model.answerTartSourcePrompt(.bundled) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled()
    }
}
