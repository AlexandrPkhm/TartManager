import TartKit

/// Detail areas available for the selected inventory entry. OCI images do not
/// have snapshots or local shared-folder settings, so their detail surface is
/// intentionally limited to its overview.
enum VMDetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case snapshots = "Snapshots"
    case sharedFolders = "Shared Folders"

    var id: Self { self }

    static func available(for entry: VMEntry) -> [VMDetailTab] {
        entry.isLocal ? allCases : [.overview]
    }
}
