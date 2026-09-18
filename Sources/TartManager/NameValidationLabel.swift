import SwiftUI

/// Shared inline validation feedback for the create and clone dialogs
/// (finding 7): the red "name unusable" label lives in one place.
struct NameValidationLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "xmark.octagon")
            .foregroundStyle(.red)
            .font(.caption)
    }
}
