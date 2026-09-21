# Tart Manager

A native macOS app that provides a Parallels-style control center for
[tart](https://github.com/cirruslabs/tart) virtual machines: list your VMs,
run, stop, suspend, edit resources, create VMs from OCI images, and manage
snapshots — without a terminal.

Early in development. Targets macOS 14+, wraps the locally installed
`tart` CLI (which must be installed separately).

## Development

Open the package root and run:

    swift build
    swift test
    swift run    # launches the app

CI runs build + tests on every pull request.

## Storage location

Tart Manager passes an explicit tart home (`TART_HOME`) to every
storage-touching tart operation, so GUI launches work even though the
shell's environment variables are not inherited. On first run an
onboarding sheet asks where VMs live — tart's own default (`~/.tart`)
is offered. The choice is validated (must exist, be a directory, and
be writable) and persisted; change it any time in Settings (⌘,).

If the configured volume is unmounted (or becomes read-only), the app
shows a dedicated "VM storage unavailable" state naming the path, with
"Choose Another Folder…" and "Retry" actions; re-mounting the volume —
or choosing another folder — recovers without a restart.

The setting is stored in `UserDefaults` under the `TartManager` domain
(`storagePath` key). Reset it for development with:

    defaults delete TartManager storagePath

## Shared folders

Each shared folder has a **Mount name**. Tart automatically mounts an
untagged folder inside the guest at `/Volumes/My Shared Files/<mount name>`;
mount names may contain spaces, such as `Host Downloads`. An optional custom
tag is an advanced manual-mount feature, not an automount setting: mount it in
the guest with `mount_virtiofs <tag> <directory>`.

## Appearance

Use the appearance icon in the main window or Settings → General → Appearance
to choose Light (sun), Dark (moon), or System (half-filled circle). The choice
is saved across launches; System follows your Mac's appearance. Settings groups
general preferences and storage controls into separate tabs.

## Error reporting

Every failed tart operation surfaces a standard report sheet: the
first stderr line as the message, an expandable raw-details block
(command, exit code, stderr, stdout — each stream captured up to
64 KiB), an explanatory hint when a known failure signature matches,
and "Copy Details", which places the full report on the clipboard for
bug reports.

The known Apple cross-version IPSW restore refusal ("An error occurred
during installation") is detected and tagged with the same-host-version
explanation plus the prebuilt-image alternative (a Cirrus Labs OCI
image).

Background polling never raises modal errors: poll failures degrade to
the storage-unavailable empty state.

Every normalized failure is also written to unified logging, so
dismissed reports stay diagnosable:

    log stream --level info --predicate 'subsystem == "app.TartManager"'

## Stop and Force Stop

Running VMs get a **Stop** button: a graceful guest shutdown with tart's
standard 30-second grace period. If the guest ignores the shutdown, tart
force-terminates the VM automatically and the list shows stopped. The
right-click menu adds **Force Stop…**, which terminates immediately and
always asks for confirmation first (unsaved guest work can be lost). A VM
that was stopped elsewhere — from a terminal, or by closing its window —
reconciles to stopped without an error, and a stop whose follow-up state
check itself fails is treated as unknown instead of raising a false error.
Stop activity is logged for diagnosis:

    log stream --predicate 'subsystem == "app.TartManager" AND category == "stop"'

## Suspend and Resume

Running VMs started by Tart Manager get a **Suspend** button: tart parks the
guest session (the window closes, the guest stops using memory) and the row
switches to **Resume**, which returns the guest to exactly the session that
was parked — no cold boot. Only VMs started with the suspend-capable
configuration can be suspended; Tart Manager always uses it, so a VM started
from a terminal without `--suspendable` produces tart's refusal with an
explanation instead. The suspend-capable configuration disables guest audio
— the accepted tradeoff, documented in the About window. If the installed
tart version does not distinguish suspended from stopped in its list output,
non-running rows offer Resume as well (`tart run` resumes a parked session
and cold-boots an actually-stopped VM). Suspend activity is logged for
diagnosis:

    log stream --predicate 'subsystem == "app.TartManager" AND category == "suspend"'

## Clipboard watchdog

Tart's clipboard sharing between you and a macOS guest goes stale after every
VM restart: the guest agent keeps running, but its channel does not survive the
stop/start (or suspend/resume) cycle. After each run Tart Manager re-kicks the
guest agent for you and installs a small LaunchAgent
(`com.tartmanager.clipboard-watchdog`) inside darwin guests that repeats that
fix after every boot and suspend/resume — including restarts made outside
Tart Manager. The repair is best-effort background hygiene: it never blocks or
fails a run, and every outcome is logged under the `clipboard` category:

    log stream --predicate 'subsystem == "app.TartManager" AND category == "clipboard"'

To uninstall the guest-side watchdog, delete
`com.tartmanager.clipboard-watchdog.plist` from the guest's
`~/Library/LaunchAgents`.

## Replace a VM's Disk

Right-click a stopped VM → **Replace Disk…** → choose a raw `.img` disk image
(tart's disk format) → type the VM's name to confirm. `tart set <name>
--disk <path>` replaces the VM's disk contents with the image — everything
currently inside the guest is destroyed, so the sheet shows a red warning and
requires the exact VM name. The replacement runs as a job with an
indeterminate progress row and cannot be cancelled once started. Running VMs
show "Replace Disk… — stop the VM first" and suspended VMs show "Replace
Disk… — resume and stop the VM first" — the action is unavailable until the
VM is stopped. Every attempt is recorded in the unified log (category
`replaceDisk`).

## Memory warnings when starting VMs

Before every Run/Resume, Tart Manager sums the memory allocations of the
running VMs plus the VM being started (each read via `tart get`, which
reports memory in MB). If the combined total reaches 90% of the host's
physical RAM, a non-blocking dialog shows the arithmetic with
**Run Anyway** / **Cancel**. The warning is advisory: tart remains the
authority, and dismissing the warning never blocks the run. The running
set comes from the polled inventory (at most a few seconds old), so a VM
started outside the app moments before may be missed, and a missing or
unreadable allocation counts as 0 MB. Assessment decisions and failures
are logged:

    log stream --predicate 'subsystem == "app.TartManager" AND category == "overcommit"'

## Pruning caches

Settings → Maintenance offers **Prune Caches…** behind a confirmation
dialog. It runs `tart prune --entries caches --older-than N` as a
cancellable job against the configured storage — VMs and snapshots are
never touched. The retention age (7, 14, or 30 days) is remembered across
launches. tart prune prints nothing on the success path, so the completion
summary ("Prune complete — freed …" / "Nothing to prune.") is derived from
the storage volume's free space measured before and after the prune;
concurrent disk activity can offset the measurement, so the summary is
informational.

## Registry accounts

Settings (⌘,) has a Registries section: enter a registry host, username,
and password/token and click Sign In. The password is delivered to tart
over its standard input (`tart login <host> --username <user>
--password-stdin`) and is never stored by Tart Manager — tart keeps the
session in your macOS Keychain. Sign Out removes tart's stored
credentials for the entered host.

tart does not expose a way to list logged-in hosts, so the pane shows no
session list; use Sign In / Sign Out per host. The buttons are disabled
while an operation is in flight and while tart (or the storage
configuration) is unavailable. Every login/logout is logged — host,
username, outcome, never the password — and failure text is scrubbed
before it reaches the error sheet:

    log stream --level info --predicate 'subsystem == "app.TartManager" AND category == "registries"'

## License

MIT — see LICENSE.
