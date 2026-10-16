import Foundation
import Darwin

/// One snapshot archive in the app-managed snapshots folder.
public struct Snapshot: Identifiable, Equatable, Sendable {
    public let vmName: String
    public let label: String?
    public let createdAt: Date?
    public let archivePath: String
    public let sizeBytes: Int64

    /// Stable identity: the archive path. A computed property — an `id`
    /// initializer parameter would be dead code, because the identity is
    /// always the path (finding 5).
    public var id: String { archivePath }

    public init(vmName: String, label: String?, createdAt: Date?,
                archivePath: String, sizeBytes: Int64) {
        self.vmName = vmName
        self.label = label
        self.createdAt = createdAt
        self.archivePath = archivePath
        self.sizeBytes = sizeBytes
    }
}

/// The app-owned snapshot catalog: a folder of `tart export` archives plus
/// sidecar metadata files written after successful exports. The catalog is
/// memoized (finding 6): an unchanged folder (fingerprinted by entry
/// name/mtime/size) is served from cache with no per-archive stat or sidecar
/// read; `writeMetadata` invalidates the cache.
public final class SnapshotStore: @unchecked Sendable {
    public let directory: String

    public init(directory: String) {
        self.directory = directory
    }

    private struct Metadata: Codable {
        let vmName: String
        let label: String?
        let createdAt: Date
    }

    private let lock = NSLock()
    private var cachedFingerprint: String?
    private var cachedCatalog: [Snapshot]?

    /// Full scans performed. Internal (`@testable`-visible) so tests pin the
    /// memoization contract (finding 6).
    private(set) var scanCount = 0

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Next archive path for a snapshot of `vmName`, sanitized and
    /// timestamped, and uniqueness-guarded (finding 9): if the candidate
    /// already exists, a `-1`, `-2`, … suffix is appended before `.tvm`, so
    /// same-second/same-label snapshots can never overwrite an existing
    /// archive.
    public func proposeArchivePath(vmName: String, label: String?, date: Date = Date()) -> String {
        let stamp = Self.timestampFormatter.string(from: date)
        let base = directory
            + "/" + Self.sanitize(vmName)
            + "__" + stamp
            + "__" + (label.map { Self.sanitize($0, fallback: "label") } ?? "unnamed")
        var candidate = base + ".tvm"
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate) {
            candidate = base + "-\(counter).tvm"
            counter += 1
        }
        return candidate
    }

    /// Persists the sidecar for a completed export. Call only after success —
    /// the catalog scan sees owned archives through their sidecars. The
    /// memo cache is invalidated so the next scan observes the new entry.
    public func writeMetadata(archivePath: String, vmName: String, label: String?,
                              createdAt: Date) throws {
        let archiveURL = URL(fileURLWithPath: archivePath).standardizedFileURL
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        guard archiveURL.deletingLastPathComponent() == directoryURL,
              archiveURL.pathExtension == "tvm" else {
            throw SnapshotStoreError.invalidArchivePath
        }
        let metadata = Metadata(vmName: vmName, label: label, createdAt: createdAt)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        let directoryDescriptor = open(directory, O_RDONLY | O_DIRECTORY)
        guard directoryDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(directoryDescriptor) }

        let sidecarName = archiveURL.lastPathComponent + ".meta.json"
        let sidecarDescriptor = sidecarName.withCString {
            openat(directoryDescriptor, $0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                   S_IRUSR | S_IWUSR)
        }
        guard sidecarDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        do {
            let handle = FileHandle(fileDescriptor: sidecarDescriptor, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            unlinkat(directoryDescriptor, sidecarName, 0)
            throw error
        }
        lock.lock()
        cachedFingerprint = nil
        cachedCatalog = nil
        lock.unlock()
    }

    private enum SnapshotStoreError: Error {
        case invalidArchivePath
    }

    /// Snapshots for every VM, newest first; memoized per folder state
    /// (finding 6). Foreign/partial archives degrade to unowned entries
    /// (finding 7); a missing folder is simply empty.
    public func snapshots() throws -> [Snapshot] {
        let fingerprint = Self.fingerprint(of: directory)
        lock.lock()
        if let cachedCatalog, let cachedFingerprint, fingerprint == cachedFingerprint {
            lock.unlock()
            return cachedCatalog
        }
        lock.unlock()
        let catalog = Self.scan(directory: directory)
        lock.lock()
        scanCount += 1
        cachedFingerprint = fingerprint
        cachedCatalog = catalog
        lock.unlock()
        return catalog
    }

    public func snapshots(forVM vmName: String) throws -> [Snapshot] {
        try snapshots().filter { $0.vmName == vmName }
    }

    /// Removes a snapshot's archive and sidecar. The ARCHIVE is removed
    /// first and the sidecar second: if the archive cannot be removed
    /// (permissions, volume error), the metadata survives and the next scan
    /// still owns the archive — it never degrades to an unowned entry. A
    /// vanished archive is a silent no-op — the scan is the truth, so ghosts
    /// never exist. The memo cache is invalidated on every path so the
    /// catalog reflects the removal immediately.
    public func delete(_ snapshot: Snapshot) throws {
        if FileManager.default.fileExists(atPath: snapshot.archivePath) {
            try FileManager.default.removeItem(atPath: snapshot.archivePath)
        }
        // Best-effort second: the scan iterates `.tvm` files only, so an
        // orphaned sidecar is invisible and never breaks the catalog.
        try? FileManager.default.removeItem(atPath: snapshot.archivePath + ".meta.json")
        lock.lock()
        cachedFingerprint = nil
        cachedCatalog = nil
        lock.unlock()
    }

    /// Replaces each disallowed character with "-" (runs collapsed, edges
    /// trimmed, empty → fallback). Replacement — not stripping — is the
    /// contract the tests and Research share (finding 2).
    static func sanitize(_ raw: String, fallback: String = "vm") -> String {
        let replaced = raw.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar)
                || scalar.value == 0x2D /* "-" */
                || scalar.value == 0x5F /* "_" */ {
                return String(scalar)
            }
            return "-"
        }.joined()
        var collapsed = ""
        var dashRun = false
        for character in replaced {
            if character == "-" {
                guard !dashRun else { continue }
                dashRun = true
            } else {
                dashRun = false
            }
            collapsed.append(character)
        }
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Cheap state fingerprint of the folder: for every `.tvm`/`.meta.json`
    /// entry, name, modification time, and size. A directory listing still
    /// happens each refresh (cheap); the per-archive stat + sidecar read +
    /// sort are skipped while the fingerprint is unchanged (finding 6).
    static func fingerprint(of directory: String) -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }
        var parts: [String] = []
        for entry in entries.sorted()
        where entry.hasSuffix(".tvm") || entry.hasSuffix(".meta.json") {
            let path = directory + "/" + entry
            let attributes = (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:]
            let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            parts.append("\(entry)|\(mtime)|\(size)")
        }
        return parts.joined(separator: ";")
    }

    /// The full scan: per-archive sidecar decode; foreign or sidecar-less
    /// archives degrade to file facts (unowned entries — finding 7).
    static func scan(directory: String) -> [Snapshot] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        var result: [Snapshot] = []
        for entry in entries where entry.hasSuffix(".tvm") {
            let archivePath = directory + "/" + entry
            let size = (DiskSpace.fileSizeBytes(atPath: archivePath) ?? 0)
            let sidecar = archivePath + ".meta.json"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: sidecar)) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let metadata = try? decoder.decode(Metadata.self, from: data) {
                    result.append(Snapshot(vmName: metadata.vmName, label: metadata.label,
                                           createdAt: metadata.createdAt,
                                           archivePath: archivePath, sizeBytes: size))
                    continue
                }
            }
            // Foreign or unreadable sidecar (incl. partial archives left by a
            // cancelled export): degrade to an UNOWNED entry.
            let attributes = try? FileManager.default.attributesOfItem(atPath: archivePath)
            let modified = attributes?[.modificationDate] as? Date
            let stem = (entry as NSString).deletingPathExtension
            result.append(Snapshot(vmName: "unknown", label: stem,
                                   createdAt: modified,
                                   archivePath: archivePath, sizeBytes: size))
        }
        return result.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
}
