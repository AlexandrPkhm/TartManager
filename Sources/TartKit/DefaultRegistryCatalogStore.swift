import Foundation
import os

/// Keeps the default registry's image list current: the saved copy when it
/// is valid, else the built-in list, and a new download once the saved copy
/// is older than `maxAge`. A failed download is logged and changes nothing,
/// because the current list still works.
public struct DefaultRegistryCatalogStore: Sendable {
    public typealias Fetch = @Sendable () async throws -> Data

    public static let remoteURL = URL(string:
        "https://raw.githubusercontent.com/AlexandrPkhm/TartManager/main/Catalog/default-registry-images.json")!
    public static let maxAge: TimeInterval = 24 * 60 * 60

    private let cacheFile: URL
    private let fetch: Fetch
    private let now: @Sendable () -> Date

    public init(cacheFile: URL, fetch: @escaping Fetch,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.cacheFile = cacheFile
        self.fetch = fetch
        self.now = now
    }

    /// The store the app uses: the saved copy lives in Application Support
    /// and the download comes from `remoteURL`.
    public static func live() -> DefaultRegistryCatalogStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DefaultRegistryCatalogStore(
            cacheFile: support.appendingPathComponent("app.TartManager/default-registry-images.json"),
            fetch: {
                var request = URLRequest(url: remoteURL)
                request.timeoutInterval = 15
                let session = URLSession(configuration: .ephemeral)
                defer { session.finishTasksAndInvalidate() }
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                return data
            })
    }

    /// The saved copy when it is valid, else the built-in list.
    public func load() -> [DefaultRegistryImage] {
        guard let data = try? Data(contentsOf: cacheFile) else {
            return DefaultRegistryCatalog.builtIn
        }
        do {
            return try DefaultRegistryCatalog.decode(data)
        } catch {
            Logger.registries.error("default registry catalog: saved copy ignored: \(String(describing: error), privacy: .public)")
            return DefaultRegistryCatalog.builtIn
        }
    }

    /// Downloads the list when the saved copy is missing or too old. Returns
    /// the new list, or nil when the list stays as it is.
    public func refreshIfStale() async -> [DefaultRegistryImage]? {
        guard isStale else { return nil }
        do {
            let data = try await fetch()
            let images = try DefaultRegistryCatalog.decode(data)
            save(data)
            Logger.registries.info("default registry catalog: downloaded \(images.count, privacy: .public) images")
            return images
        } catch {
            Logger.registries.error("default registry catalog: download failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private var isStale: Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path),
              let modified = attributes[.modificationDate] as? Date else { return true }
        let age = now().timeIntervalSince(modified)
        // A negative age means the clock moved: the date cannot be trusted.
        return age < 0 || age >= Self.maxAge
    }

    /// A failed write only costs a new download on the next refresh.
    private func save(_ data: Data) {
        do {
            try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: cacheFile, options: .atomic)
        } catch {
            Logger.registries.error("default registry catalog: save failed: \(String(describing: error), privacy: .public)")
        }
    }
}
