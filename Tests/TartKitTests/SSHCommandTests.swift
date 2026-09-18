import Testing
@testable import TartKit

@Suite struct SSHCommandTests {
    @Test func assemblesUserAtIP() {
        #expect(SSHCommand.text(user: "admin", ip: "192.168.64.2") == "ssh admin@192.168.64.2")
        #expect(SSHCommand.text(user: "ci", ip: "10.0.0.5") == "ssh ci@10.0.0.5")
    }
}
