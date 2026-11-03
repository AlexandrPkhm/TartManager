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

    private func makeStore(_ stub: FetchStub, now: Date = Date()) -> DefaultRegistryCatalogStore {
        DefaultRegistryCatalogStore(cacheFile: cacheFile,
                                    fetch: { try stub.fetch() },
                                    now: { now })
    }

    private func writeCache(_ data: Data, modified: Date) throws {
        try FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: cacheFile)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: cacheFile.path)
    }

    @Test func loadUsesBuiltInListWithoutSavedCopy() {
        let store = makeStore(FetchStub(.success(catalog("New"))))
        #expect(store.load() == DefaultRegistryCatalog.builtIn)
    }

    @Test func loadUsesValidSavedCopy() throws {
        try writeCache(catalog("Saved"), modified: Date())
        let store = makeStore(FetchStub(.success(catalog("New"))))
        #expect(store.load().map(\.label) == ["Saved"])
    }

    @Test func loadIgnoresBadSavedCopy() throws {
        try writeCache(Data("broken".utf8), modified: Date())
        let store = makeStore(FetchStub(.success(catalog("New"))))
        #expect(store.load() == DefaultRegistryCatalog.builtIn)
    }

    @Test func refreshDownloadsAndSavesWithoutSavedCopy() async {
        let stub = FetchStub(.success(catalog("New")))
        let store = makeStore(stub)
        let images = await store.refreshIfStale()
        #expect(images?.map(\.label) == ["New"])
        #expect(store.load().map(\.label) == ["New"])
        #expect(stub.calls == 1)
    }

    @Test func refreshSkipsDownloadWhileSavedCopyIsFresh() async throws {
        let now = Date()
        try writeCache(catalog("Saved"), modified: now.addingTimeInterval(-(DefaultRegistryCatalogStore.maxAge - 60)))
        let stub = FetchStub(.success(catalog("New")))
        let images = await makeStore(stub, now: now).refreshIfStale()
        #expect(images == nil)
        #expect(stub.calls == 0)
    }

    @Test func refreshDownloadsWhenSavedCopyIsOldOrDatedInTheFuture() async throws {
        let now = Date()
        for modified in [now.addingTimeInterval(-DefaultRegistryCatalogStore.maxAge),
                         now.addingTimeInterval(3_600)] {
            try writeCache(catalog("Saved"), modified: modified)
            let stub = FetchStub(.success(catalog("New")))
            let images = await makeStore(stub, now: now).refreshIfStale()
            #expect(images?.map(\.label) == ["New"])
        }
    }

    @Test func failedDownloadKeepsSavedCopy() async throws {
        let now = Date()
        try writeCache(catalog("Saved"), modified: now.addingTimeInterval(-2 * DefaultRegistryCatalogStore.maxAge))
        let store = makeStore(FetchStub(.failure(URLError(.notConnectedToInternet))), now: now)
        let images = await store.refreshIfStale()
        #expect(images == nil)
        #expect(store.load().map(\.label) == ["Saved"])
    }

    @Test func badDownloadKeepsSavedCopy() async throws {
        let now = Date()
        try writeCache(catalog("Saved"), modified: now.addingTimeInterval(-2 * DefaultRegistryCatalogStore.maxAge))
        let bad = Data(#"{"schemaVersion":2,"images":[]}"#.utf8)
        let store = makeStore(FetchStub(.success(bad)), now: now)
        let images = await store.refreshIfStale()
        #expect(images == nil)
        #expect(store.load().map(\.label) == ["Saved"])
    }
}
