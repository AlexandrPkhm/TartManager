import SwiftUI
import TartKit

/// The standard failure report: message, optional hint, raw details, copy.
struct ErrorReportSheet: View {
    let error: TartOperationError
    let onClose: () -> Void
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("tart operation failed: \(error.operation)")
                    .font(.headline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            Text(error.message)
            if let hint = error.hint {
                Label {
                    Text(hint).font(.callout)
                } icon: {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            DisclosureGroup("Details", isExpanded: $showDetails) {
                ScrollView {
                    Text(error.rawDetails)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(6)
                }
                .frame(height: 160)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                CopyButton(value: error.copyReport(), label: "Copy Details")
                Spacer()
                Button("Close") { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
