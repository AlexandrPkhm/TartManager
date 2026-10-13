import Testing
import Foundation
@testable import TartKit

@Suite struct TartCommandEnvironmentTests {
    @Test func environmentCarriesTartHome() {
        let env = TartCommandEnvironment(storagePath: "/Volumes/SSD/Work/VMs/Tart")
        #expect(env.environment == ["TART_HOME": "/Volumes/SSD/Work/VMs/Tart"])
    }

    @Test func injectionReachesTheSubprocess() throws {
        let storage = "/tmp/tastic-\(UUID().uuidString)"
        let env = TartCommandEnvironment(storagePath: storage)
        let result = try ProcessRunner().run(
            "/bin/sh", ["-c", "echo $TART_HOME"], environment: env.environment)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == storage)
    }

    @Test func manualCleanupDisablesTartsAutomaticReclamation() throws {
        let env = TartCommandEnvironment(
            storagePath: "/tmp/manual-cache-storage",
            automaticCachePruningEnabled: false)
        let result = try ProcessRunner().run(
            "/bin/sh", ["-c", "printf '%s|%s' \"$TART_HOME\" \"$TART_NO_AUTO_PRUNE\""],
            environment: env.environment)

        #expect(result.stdout == "/tmp/manual-cache-storage|1")
    }

    @Test func automaticCleanupDoesNotDisableTartsReclamation() {
        let env = TartCommandEnvironment(
            storagePath: "/tmp/automatic-cache-storage",
            automaticCachePruningEnabled: true)

        #expect(env.environment["TART_NO_AUTO_PRUNE"] == nil)
    }
}
