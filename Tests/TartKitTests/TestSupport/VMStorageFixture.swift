import Foundation

/// Seeds a temp `TART_HOME` layout with a local VM directory and its
/// `config.json`, so tests can exercise the storage-reading paths (guest-OS
/// detection, run configuration) hermetically — no real tart, no real VM.
enum VMStorageFixture {
    /// Creates `<root>/vms/<name>/config.json` — containing `{"os": "<os>"}`
    /// when `os` is non-nil, no config file otherwise — and returns the
    /// storage root path for `TART_HOME` injection.
    static func make(storageWithVM name: String, os: String?) -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tartmanager-tests-\(UUID().uuidString)").path
        let vmDirectory = root + "/vms/" + name
        try! FileManager.default.createDirectory(
            atPath: vmDirectory, withIntermediateDirectories: true)
        if let os {
            let json = #"{"os":"\#(os)"}"#
            try! json.write(toFile: vmDirectory + "/config.json",
                            atomically: true, encoding: .utf8)
        }
        return root
    }
}
