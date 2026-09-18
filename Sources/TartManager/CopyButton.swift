import SwiftUI
import AppKit

/// Shared clipboard affordance: writes `value` to the pasteboard and flips
/// to "Copied" for 2 s. Used by PrerequisiteBanner and ErrorReportSheet, so
/// the pasteboard behavior is defined once.
struct CopyButton: View {
    let value: String
    var label: String = "Copy"
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : label) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        }
    }
}
