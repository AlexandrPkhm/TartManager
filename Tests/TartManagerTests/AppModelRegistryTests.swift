import Testing
import Foundation
@testable import TartKit
@testable import TartManager

@Suite @MainActor struct AppModelRegistryTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppModelRegistryTests-\(UUID().uuidString)")!
    }

    private func makeStore(fetch: @escaping DefaultRegistryCatalogStore.Fetch) -> DefaultRegistryCatalogStore {
        DefaultRegistryCatalogStore(
            cacheFile: FileManager.default.temporaryDirectory
                .appendingPathComponent("registry-model-\(UUID().uuidString)/images.json"),
            settings: AppSettings(defaults: makeDefaults()),
            fetch: fetch)
    }

    private func makeModel(defaults: UserDefaults? = nil,
                           store: DefaultRegistryCatalogStore? = nil) -> AppModel {
        AppModel(settings: AppSettings(defaults: defaults ?? makeDefaults()),
                 defaultRegistryStore: store ?? makeStore(fetch: { throw URLError(.notConnectedToInternet) }))
    }

    /// A model with usable storage and a tart stub.
    private func makeReadyModel(script: String) throws -> AppModel {
        let storage = FileManager.default.temporaryDirectory
            .appendingPathComponent("registry-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let binary = storage.appendingPathComponent("tart").path
        try script.write(toFile: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)
        let model = makeModel()
        #expect(model.attemptChooseStorage(path: storage.path) == .valid(path: storage.path))
        model.prerequisite = .ok(version: TartVersion(major: 2, minor: 32, patch: 0),
                                 binaryPath: binary, source: .installed)
        return model
    }

    @Test func modeDefaultsToDefaultRegistryAndPersists() {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        #expect(model.registryMode == .standard)
        model.setRegistryMode(.custom)
        #expect(model.registryMode == .custom)
        #expect(makeModel(defaults: defaults).registryMode == .custom)
    }

    @Test func unknownStoredModeUsesDefaultRegistry() {
        let defaults = makeDefaults()
        defaults.set("other", forKey: "registryMode")
        #expect(makeModel(defaults: defaults).registryMode == .standard)
    }

    @Test func refreshReplacesTheList() async {
        let data = Data("""
        {"schemaVersion":1,"images":[{"label":"New","reference":"ghcr.io/cirruslabs/x:latest"}]}
        """.utf8)
        let model = makeModel(store: makeStore(fetch: { data }))
        #expect(model.defaultRegistryImages == DefaultRegistryCatalog.builtIn)
        await model.refreshDefaultRegistryImages()
        #expect(model.defaultRegistryImages.map(\.label) == ["New"])
    }

    @Test func failedRefreshKeepsTheList() async {
        let model = makeModel()
        await model.refreshDefaultRegistryImages()
        #expect(model.defaultRegistryImages == DefaultRegistryCatalog.builtIn)
    }

    @Test func pullIsRefusedWithoutTartOrStorage() {
        let model = makeModel()
        #expect(model.pullBlockReason(reference: "ghcr.io/cirruslabs/x:latest") != nil)
        #expect(model.startPull(reference: "ghcr.io/cirruslabs/x:latest") != nil)
        #expect(model.jobManager.jobs.isEmpty)
    }

    @Test func pullIsRefusedForAnInvalidReference() throws {
        let model = try makeReadyModel(script: "#!/bin/sh\nexit 0\n")
        #expect(model.pullBlockReason(reference: "-bad") == "The image reference is not valid.")
    }

    @Test func pullRunsAsJobAndRefusesASecondPullOfTheSameImage() async throws {
        let model = try makeReadyModel(script: "#!/bin/sh\nsleep 30\n")
        let reference = "ghcr.io/cirruslabs/x:latest"
        #expect(model.startPull(reference: reference) == nil)
        #expect(model.jobManager.jobs.first?.kind == .pull(reference: reference))
        #expect(model.pullBlockReason(reference: reference) == "This image is already being pulled.")
        #expect(model.pullBlockReason(reference: "ghcr.io/cirruslabs/y:latest") == nil)
        if let id = model.jobManager.jobs.first?.id { model.jobManager.cancel(id: id) }
        await model.jobManager.awaitIdle(timeout: 10)
    }
}
