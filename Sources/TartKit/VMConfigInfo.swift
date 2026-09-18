import Foundation

/// Read-only view of a VM's configuration (`tart get --format json`,
/// tart 2.32.0). Mirrors Get.swift's VMInfo exactly: capital-first keys,
/// `Memory` in MB (tart divides bytes by 1024²), `Display` and `Size` as
/// strings. All keys pinned here; every field optional so schema drift
/// degrades one summary row, not the pane.
public struct VMConfigInfo: Equatable, Sendable {
    public let os: String?          // "darwin" | "linux"
    public let cpuCount: Int?
    public let memoryMB: Int?       // MB — already converted by tart
    public let diskGB: Int?         // allocated GB (informational; the pane uses VMEntry)
    public let diskFormat: String?
    public let sizeText: String?    // on-disk GB, 3-decimal string (informational)
    public let displayText: String? // "1024x768" with optional pt/px suffix
    public let running: Bool?
    public let state: String?

    public init(os: String? = nil, cpuCount: Int? = nil, memoryMB: Int? = nil,
                diskGB: Int? = nil, diskFormat: String? = nil, sizeText: String? = nil,
                displayText: String? = nil, running: Bool? = nil, state: String? = nil) {
        self.os = os
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskGB = diskGB
        self.diskFormat = diskFormat
        self.sizeText = sizeText
        self.displayText = displayText
        self.running = running
        self.state = state
    }
}

extension VMConfigInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case os = "OS"
        case cpuCount = "CPU"
        case memoryMB = "Memory"
        case diskGB = "Disk"
        case diskFormat = "DiskFormat"
        case sizeText = "Size"
        case displayText = "Display"
        case running = "Running"
        case state = "State"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        os = c.optional(String.self, for: .os)
        cpuCount = c.optional(Int.self, for: .cpuCount)
        memoryMB = c.optional(Int.self, for: .memoryMB)
        diskGB = c.optional(Int.self, for: .diskGB)
        diskFormat = c.optional(String.self, for: .diskFormat)
        sizeText = c.optional(String.self, for: .sizeText)
        displayText = c.optional(String.self, for: .displayText)
        running = c.optional(Bool.self, for: .running)
        state = c.optional(String.self, for: .state)
    }
}

/// Defensive decode: absent, null, or wrong-typed values all yield nil
/// (a schema drift degrades one row, never the pane).
private extension KeyedDecodingContainer {
    func optional<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
