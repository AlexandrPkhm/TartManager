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
}
