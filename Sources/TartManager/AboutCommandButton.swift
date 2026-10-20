import SwiftUI

/// **Tart Manager → About Tart Manager**: opens Settings on the About tab.
/// A separate view, because `openSettings` is read from the environment.
struct AboutCommandButton: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("About Tart Manager") {
            model.showAbout()
            openSettings()
        }
    }
}
