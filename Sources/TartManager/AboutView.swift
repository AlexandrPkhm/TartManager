import SwiftUI

/// About sheet carrying the run-configuration note (suspend-capable runs
/// disable guest audio; macOS guests only), the two-tier stop semantics, and
/// the suspend/resume behavior.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: AppIcon.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                Text("Tart Manager")
                    .font(.title2).bold()
            }
            Text("A native control center for tart VMs.")
                .foregroundStyle(.secondary)
            Divider()
            Text("Running VMs").font(.headline)
            Text("""
            macOS VMs you start from Tart Manager run in the \
            suspend-capable configuration so their sessions can be \
            suspended and resumed later. As a tradeoff, audio inside \
            the macOS guest is disabled while it runs. Linux guests \
            run normally — tart only supports suspend for macOS.
            """)
            Text("Stopping VMs").font(.headline)
            Text("""
            Stop initiates a graceful guest shutdown. If the guest hasn't \
            shut down within tart's 30-second grace period, tart \
            force-terminates the VM automatically. Force Stop terminates \
            immediately and can lose unsaved guest work, so it always \
            asks for confirmation first.
            """)
            Text("Suspending VMs").font(.headline)
            Text("""
            Suspend parks a running macOS VM's session: the VM window \
            closes and the guest stops using memory until you click \
            Resume, which returns it to exactly where you left off — no \
            cold boot. Suspend appears only when Tart Manager confirms \
            that the running macOS VM was started with --suspendable. \
            Tart Manager uses this configuration for macOS guests. The \
            button is hidden for Linux guests and sessions whose suspend \
            configuration cannot be confirmed. This configuration disables guest \
            audio — the accepted tradeoff.
            """)
            // Replacing a VM's Disk: the destructive disk-replacement flow
            // and its data-loss semantics, documented in-app.
            Text("Replacing a VM's Disk")
                .font(.headline)
            Text("Replace Disk (context menu on a stopped VM) copies a chosen raw disk "
                 + "image (.img) over the VM's current disk, permanently destroying its "
                 + "contents. The sheet shows a red warning and requires typing the VM's "
                 + "name. Running or suspended VMs must be stopped first; once started, "
                 + "the replacement cannot be cancelled.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Memory warnings").font(.headline)
            Text("""
            Before starting a VM, Tart Manager adds its memory allocation \
            to what the running VMs already use. When the combined total \
            reaches 90% of this Mac's physical RAM, a warning shows the \
            arithmetic and lets you continue or cancel. The warning is \
            advisory only — tart decides whether the run actually \
            succeeds, and you can always proceed.
            """)
            Text("Pruning caches").font(.headline)
            Text("""
            Settings → Maintenance prunes OCI/IPSW cache entries older \
            than the chosen retention age (7, 14, or 30 days — remembered \
            across launches). VMs and snapshots are never touched. tart \
            prune prints nothing while it works, so the completed job row \
            reports the reclaimed space measured from the storage volume's \
            free space before and after pruning; concurrent disk activity \
            can offset that measurement, so treat it as informational.
            """)
            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
