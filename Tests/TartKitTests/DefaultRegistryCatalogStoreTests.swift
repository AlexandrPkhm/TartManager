import Testing
import Foundation
@testable import TartKit

@Suite struct DefaultRegistryCatalogStoreTests {
    /// Counts the downloads and returns a preset result.
    final class FetchStub: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private let result: Result<Data, Error>

        init(_ result: Result<Data, Error>) { self.result = result }

        var calls: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }

        func fetch() throws -> Data {
            lock.lock()
            count += 1
            lock.unlock()
            return try result.get()
        }
    }

    private let cacheFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("default-registry-store-\(UUID().uuidString)")
        .appendingPathComponent("nested/images.json")

    private func catalog(_ label: String) -> Data {
        Data("""
        {"schemaVersion":1,"images":[{"label":"\(label)","reference":"ghcr.io/cirruslabs/x:latest"}]}
        """.utf8)
    }

    private let settings = AppSettings(
        defaults: UserDefaults(suiteName: "DefaultRegistryCatalogStoreTests-\(UUID().uuidString)")!)

    private func makeStore(_ stub: FetchStub, now: Date = Date()) -> DefaultRegistryCatalogStore {
        DefaultRegistryCatalogStore(cacheFile: cacheFile,
                                    settings: settings,
                                    fetch: { try stub.fetch() },
                                    now: { now })
    }

    private func writeCache(_ data: Data) throws {
        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: cacheFile)
    }

    @Test func loadUsesBuiltInListWithoutSavedCopy() {
        let store = makeStore(FetchStub(.success(catalog("New"))))
        #expect(store.load() == DefaultRegistryCatalog.builtIn)
    }

    @Test func loadUsesValidSavedCopy() throws {
        try writeCache(catalog("Saved"))
        let store = makeStore(FetchStub(.success(catalog("New"))))
        #expect(store.load().map(\.label) == ["Saved"])
    }

    @Test func loadIgnoresBadSavedCopy() throws {
        try writeCache(Data("broken".utf8))
        let store = makeStore(FetchStub(.success(catalog("New"))))
        #expect(store.load() == DefaultRegistryCatalog.builtIn)
    }

    @Test func refreshDownloadsAndSavesOnFirstAttempt() async {
        let now = Date()
        let stub = FetchStub(.success(catalog("New")))
        let store = makeStore(stub, now: now)
        let images = await store.refreshIfDue()
        #expect(images?.map(\.label) == ["New"])
        #expect(store.load().map(\.label) == ["New"])
        #expect(stub.calls == 1)
        #expect(settings.defaultRegistryRefreshAttempt == now)
    }

    @Test func refreshSkipsDownloadInsideTheLimit() async {
        let now = Date()
        settings.defaultRegistryRefreshAttempt = now.addingTimeInterval(-(DefaultRegistryCatalogStore.maxAge - 60))
        let stub = FetchStub(.success(catalog("New")))
        let images = await makeStore(stub, now: now).refreshIfDue()
        #expect(images == nil)
        #expect(stub.calls == 0)
    }

    @Test func refreshDownloadsWhenAttemptIsOldOrDatedInTheFuture() async {
        let now = Date()
        for attempt in [now.addingTimeInterval(-DefaultRegistryCatalogStore.maxAge),
                        now.addingTimeInterval(3_600)] {
            settings.defaultRegistryRefreshAttempt = attempt
            let stub = FetchStub(.success(catalog("New")))
            let images = await makeStore(stub, now: now).refreshIfDue()
            #expect(images?.map(\.label) == ["New"])
            #expect(stub.calls == 1)
        }
    }

    @Test func failedDownloadKeepsSavedCopyAndWaitsForTheLimit() async throws {
        let now = Date()
        try writeCache(catalog("Saved"))
        let stub = FetchStub(.failure(URLError(.notConnectedToInternet)))
        let store = makeStore(stub, now: now)
        #expect(await store.refreshIfDue() == nil)
        #expect(await store.refreshIfDue() == nil)
        #expect(stub.calls == 1)
        #expect(store.load().map(\.label) == ["Saved"])
    }

    @Test func failedSaveStillWaitsForTheLimit() async throws {
        let now = Date()
        // A regular file in place of the parent folder makes the save fail.
        let parent = cacheFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: parent)
        let stub = FetchStub(.success(catalog("New")))
        let store = makeStore(stub, now: now)
        #expect(await store.refreshIfDue()?.map(\.label) == ["New"])
        #expect(await store.refreshIfDue() == nil)
        #expect(stub.calls == 1)
    }

    @Test func badDownloadKeepsSavedCopy() async throws {
        try writeCache(catalog("Saved"))
        let bad = Data(#"{"schemaVersion":2,"images":[]}"#.utf8)
        let store = makeStore(FetchStub(.success(bad)))
        #expect(await store.refreshIfDue() == nil)
        #expect(store.load().map(\.label) == ["Saved"])
    }
}
