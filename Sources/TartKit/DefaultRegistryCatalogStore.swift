import Foundation
import os

/// Keeps the default registry's image list current: the saved copy when it
/// is valid, else the built-in list, and at most one download attempt per
/// `maxAge`. The limit uses the recorded attempt, not the saved file, so a
/// failed download or a failed save also waits. A failure is logged and
/// changes nothing, because the current list still works.
public struct DefaultRegistryCatalogStore: Sendable {
    public typealias Fetch = @Sendable () async throws -> Data

    public static let remoteURL = URL(string:
        "https://raw.githubusercontent.com/AlexandrPkhm/TartManager/main/Catalog/default-registry-images.json")!
    public static let maxAge: TimeInterval = 24 * 60 * 60

    private let cacheFile: URL
    private let settings: AppSettings
    private let fetch: Fetch
    private let now: @Sendable () -> Date

    public init(cacheFile: URL, settings: AppSettings, fetch: @escaping Fetch,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.cacheFile = cacheFile
        self.settings = settings
        self.fetch = fetch
        self.now = now
    }

    /// The store the app uses: the saved copy lives in Application Support
    /// and the download comes from `remoteURL`.
    public static func live(settings: AppSettings) -> DefaultRegistryCatalogStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return DefaultRegistryCatalogStore(
            cacheFile: support.appendingPathComponent("app.TartManager/default-registry-images.json"),
            settings: settings,
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

    /// Downloads the list when the last attempt is older than `maxAge`.
    /// Returns the new list, or nil when the list stays as it is.
    public func refreshIfDue() async -> [DefaultRegistryImage]? {
        guard isDue else { return nil }
        // Recorded before the request, so a failure also counts.
        settings.defaultRegistryRefreshAttempt = now()
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

    private var isDue: Bool {
        guard let attempt = settings.defaultRegistryRefreshAttempt else { return true }
        let age = now().timeIntervalSince(attempt)
        // A negative age means the clock moved: the date cannot be trusted.
        return age < 0 || age >= Self.maxAge
    }

    /// A failed write only costs the saved copy: the next launch uses the
    /// previous list until the next attempt is due.
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
