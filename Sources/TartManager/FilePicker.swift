import AppKit
import UniformTypeIdentifiers

enum FilePicker {
    /// Runs a single-file NSOpenPanel filtered by extension; returns the path or nil.
    @MainActor
    static func chooseFile(title: String, allowedExtensions: [String]) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        // `UTType(filenameExtension:)` returns nil for undeclared extensions
        // (.tvm is not system-declared); the conformingTo: variant creates a
        // dynamic .data-conforming type so the filter actually applies
        // (finding 12). Fallback to .data guarantees a non-empty filter.
        panel.allowedContentTypes = allowedExtensions.map { ext in
            UTType(filenameExtension: ext, conformingTo: .data) ?? .data
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }
}
