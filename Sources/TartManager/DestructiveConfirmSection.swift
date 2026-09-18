import SwiftUI

/// Shared red typed-name confirmation section for the destructive sheets
/// (Replace Disk, Delete VM, Restore Snapshot) — one implementation of the
/// red warning + typed-name field instead of a fourth copy (finding 6).
/// Purely presentational: the gate logic stays in the tested TartKit
/// functions each sheet already uses.
struct DestructiveConfirmSection: View {
    /// The red data-loss warning; nil renders no warning line (the restore
    /// sheet explains the replacement in its Safety section instead).
    let warning: String?
    /// The field's prompt, e.g. "Type “vm-a” to confirm".
    let prompt: String
    @Binding var typedName: String

    var body: some View {
        Group {
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            TextField(prompt, text: $typedName)
        }
    }
}
