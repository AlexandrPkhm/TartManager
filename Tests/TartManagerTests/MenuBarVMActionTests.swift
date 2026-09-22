import Testing
@testable import TartKit
@testable import TartManager

@Suite struct MenuBarVMActionTests {
    private func vm(name: String = "macos", source: String = "local",
                    running: Bool, state: String) -> VMEntry {
        VMEntry(name: name, source: source, running: running, state: state,
                diskSize: 64, diskUsage: 16, accessed: nil)
    }

    @Test func mapsOnlyLocalVMsToTheirSingleSafeLifecycleAction() {
        #expect(MenuBarVMAction(entry: vm(running: false, state: "stopped")) == .run(title: "Run"))
        #expect(MenuBarVMAction(entry: vm(running: false, state: "suspended")) == .run(title: "Resume"))
        #expect(MenuBarVMAction(entry: vm(running: true, state: "running")) == .stop)
        #expect(MenuBarVMAction(entry: vm(source: "ghcr.io/cirruslabs/macos", running: false,
                                           state: "stopped")) == nil)
    }
}
