import Foundation

/// Pure renderers for the guest-side payload that keeps Tart clipboard
/// sharing alive across VM restarts. The tart-guest-agent's SPICE channel
/// is recreated by every VM stop/start and suspend/resume while the agent
/// process keeps running with a dead channel; restarting the agent via
/// `launchctl kickstart` re-opens it (the documented tart workaround).
///
/// Everything here is a string built on the host and executed inside the
/// guest through `TartClient.exec` (guest `sh -lc`): constructs such as
/// `$(id -u)` and `$HOME` expand against the guest, never the host — and
/// the host never shell-interprets anything because `ProcessRunner` passes
/// argv directly. The installer is idempotent: same files, same label,
/// bootout-then-bootstrap.
public enum GuestClipboardWatchdog {
    /// LaunchAgent label the watchdog installs under inside the guest.
    public static let label = "com.tartmanager.clipboard-watchdog"

    /// Readiness probe executed via `tart exec`; the guest agent answers
    /// with the echoed word when its RPC channel (vsock) is live.
    public static let readinessProbe = "echo ready"

    /// The documented per-boot channel re-establishment command, run through
    /// `tart exec` under the guest's `sh -lc`. Deliberately backgrounded:
    /// `kickstart -k` restarts the guest agent, which is also the process
    /// serving this very `tart exec` RPC — a foreground kick would kill the
    /// exec's own server, so its exit status could never be delivered (the
    /// exec would hang until the client's timeout). Detaching the kill lets
    /// the exec return immediately; the restart lands a moment later, which
    /// the coordinator's re-readiness poll observes.
    public static let agentKickstartCommand =
        "launchctl kickstart -k gui/$(id -u)/org.cirruslabs.tart-guest-agent >/dev/null 2>&1 &"

    /// The watchdog shell script written into the guest. Two branches, one
    /// kickstart: first load after login waits for the session and kicks
    /// once (covers boots); later runs kick only when the wall clock jumped
    /// by more than 25 s — launchd invokes us every 15 s, so a larger gap
    /// means the VM was suspended and resumed with the clock stepped
    /// (covers resumes, including ones Tart Manager did not initiate).
    public static func watchdogScript() -> String {
        """
        #!/bin/sh
        # Tart Manager clipboard watchdog: re-establishes the tart-guest-agent
        # vdagent (clipboard) link after every VM boot and suspend/resume.
        # Installed by Tart Manager via `tart exec`; remove by deleting the
        # LaunchAgent plist in ~/Library/LaunchAgents.
        state="$HOME/.tartmanager-clipboard-watchdog.state"
        now=$(date +%s)
        if [ -f "$state" ]; then
            last=$(cat "$state" 2>/dev/null || echo 0)
            printf '%s\\n' "$now" > "$state"
            # launchd runs this every 15 s; a gap over 25 s means the clock
            # stepped (the VM was suspended and resumed): the agent's channel
            # is stale, so restart it.
            if [ $((now - last)) -gt 25 ]; then
                launchctl kickstart -k "gui/$(id -u)/org.cirruslabs.tart-guest-agent" >/dev/null 2>&1 || true
            fi
        else
            # First run after login (boot): give launchd a moment to start
            # the guest agent, then restart it once so its channel is live.
            printf '%s\\n' "$now" > "$state"
            sleep 10
            launchctl kickstart -k "gui/$(id -u)/org.cirruslabs.tart-guest-agent" >/dev/null 2>&1 || true
        fi
        exit 0
        """
    }

    /// The LaunchAgent plist written into the guest. `ProgramArguments`
    /// carries a literal `$HOME` that the installer's unquoted heredoc
    /// expands at install time — the guest user's home is unknown to the
    /// host and launchd does not expand variables itself.
    public static func launchAgentPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/sh</string>
                <string>$HOME/Library/Application Support/TartManager/clipboard-watchdog.sh</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StartInterval</key>
            <integer>15</integer>
            <key>StandardOutPath</key>
            <string>/tmp/tartmanager-clipboard-watchdog.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/tartmanager-clipboard-watchdog.log</string>
        </dict>
        </plist>
        """
    }

    /// The single `sh -lc` payload, executed via `tart exec`, that installs
    /// or refreshes the watchdog in the guest. The script heredoc is quoted
    /// (`<<'TM-SCRIPT'`) so nothing expands at install time; the plist
    /// heredoc is unquoted (`<<TM-PLIST`) so its `$HOME` expands at install
    /// time (the plist contains no other `$` or backticks). bootout ignores
    /// absence, making the whole payload safe to re-run on every launch.
    public static func installScript() -> String {
        var lines: [String] = []
        lines.append("mkdir -p \"$HOME/Library/Application Support/TartManager\"")
        lines.append("mkdir -p \"$HOME/Library/LaunchAgents\"")
        lines.append("cat > \"$HOME/Library/Application Support/TartManager/clipboard-watchdog.sh\" <<'TM-SCRIPT'")
        lines.append(watchdogScript())
        lines.append("TM-SCRIPT")
        lines.append("chmod +x \"$HOME/Library/Application Support/TartManager/clipboard-watchdog.sh\"")
        lines.append("cat > \"$HOME/Library/LaunchAgents/\(label).plist\" <<TM-PLIST")
        lines.append(launchAgentPlist())
        lines.append("TM-PLIST")
        lines.append("launchctl bootout gui/$(id -u)/\(label) 2>/dev/null || true")
        lines.append("launchctl bootstrap gui/$(id -u) \"$HOME/Library/LaunchAgents/\(label).plist\"")
        return lines.joined(separator: "\n")
    }
}
