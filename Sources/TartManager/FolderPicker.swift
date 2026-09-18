import AppKit

enum FolderPicker {
    /// Runs a single-folder NSOpenPanel and returns the chosen path, or nil.
    @MainActor
    static func chooseFolder(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
