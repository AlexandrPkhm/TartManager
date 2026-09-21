import Testing
import Foundation
@testable import TartKit

@Suite struct GuestClipboardWatchdogTests {
    @Test func exactCommandConstantsMatchTheGuestAgentLabel() {
        #expect(GuestClipboardWatchdog.label == "com.tartmanager.clipboard-watchdog")
        #expect(GuestClipboardWatchdog.readinessProbe == "echo ready")
        // Backgrounded on purpose: a foreground kick kills the very guest
        // agent serving this exec's RPC, so the exec could never return its
        // exit status (it would hang until the client timeout).
        #expect(GuestClipboardWatchdog.agentKickstartCommand
            == "launchctl kickstart -k gui/$(id -u)/org.cirruslabs.tart-guest-agent >/dev/null 2>&1 &")
    }

    @Test func watchdogScriptKicksOnBootAndOnClockJump() {
        let script = GuestClipboardWatchdog.watchdogScript()
        // Boot branch: first load waits for the session, then kicks once.
        #expect(script.contains("sleep 10"))
        // Resume branch: a gap over 25 s (15 s StartInterval) means the clock stepped.
        #expect(script.contains("-gt 25"))
        // Both branches restart the guest agent's launchd job.
        #expect(script.contains("launchctl kickstart -k \"gui/$(id -u)/org.cirruslabs.tart-guest-agent\""))
    }

    @Test func launchAgentPlistIsParseableAndWiredToTheWatchdog() throws {
        let plist = GuestClipboardWatchdog.launchAgentPlist()
        let data = try #require(plist.data(using: .utf8))
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let dict = try #require(parsed)
        #expect(dict["Label"] as? String == "com.tartmanager.clipboard-watchdog")
        #expect(dict["RunAtLoad"] as? Bool == true)
        #expect(dict["StartInterval"] as? Int == 15)
        #expect((dict["ProgramArguments"] as? [String])
            == ["/bin/sh", "$HOME/Library/Application Support/TartManager/clipboard-watchdog.sh"])
        #expect(dict["StandardErrorPath"] as? String == "/tmp/tartmanager-clipboard-watchdog.log")
    }

    @Test func installScriptWritesFilesAndRebootstrapsIdempotently() {
        let install = GuestClipboardWatchdog.installScript()
        #expect(install.contains("mkdir -p \"$HOME/Library/Application Support/TartManager\""))
        #expect(install.contains("mkdir -p \"$HOME/Library/LaunchAgents\""))
        // Script heredoc is quoted: guest variables survive to run time.
        #expect(install.contains("<<'TM-SCRIPT'"))
        // Plist heredoc is unquoted so $HOME expands at install time.
        #expect(install.contains("<<TM-PLIST"))
        #expect(install.contains("launchctl bootout gui/$(id -u)/com.tartmanager.clipboard-watchdog"))
        #expect(install.contains("launchctl bootstrap gui/$(id -u)"))
    }
}
