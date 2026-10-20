import SwiftUI
import AppKit

/// Shared clipboard affordance: writes `value` to the pasteboard and flips
/// to "Copied" for 2 s. Used by PrerequisiteBanner and ErrorReportSheet, so
/// the pasteboard behavior is defined once. With `systemImage`, it shows only
/// an icon that flips to a checkmark.
struct CopyButton: View {
    let value: String
    var label: String = "Copy"
    var systemImage: String? = nil
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            if let systemImage {
                Label(copied ? "Copied" : label, systemImage: copied ? "checkmark" : systemImage)
                    .labelStyle(.iconOnly)
            } else {
                Text(copied ? "Copied" : label)
            }
        }
    }
}
