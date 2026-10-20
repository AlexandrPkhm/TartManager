# Tart Manager

Tart Manager is a native macOS control center for people who run
[tart](https://github.com/openai/tart) virtual machines and want to
manage them without the terminal.

Run, stop, suspend, configure, create, and maintain your local tart VMs from
one app. Tart Manager keeps tart as the VM engine; it gives its local
inventory a macOS interface.

<p align="center">
  <img
    src="Assets/TartManager.png"
    alt="Tart Manager showing local virtual machines and storage settings"
    width="900">
</p>

> **Status:** Tart Manager is in early development. Feedback and bug reports
> are welcome.

## What you can do

- See your local VM inventory and run, resume, suspend, gracefully stop, or
  force-stop a VM.
- Create VMs from OCI images or IPSW restore images, import `.tvm` archives,
  and clone existing VMs.
- Configure VM resources, hardware identity, and shared folders; replace a
  stopped VM's disk when needed.
- Create, restore, and remove snapshots before experimenting with a VM.
- Manage registry sign-in, cache cleanup, storage location, and appearance in
  Settings.
- Control common VM actions from the macOS menu bar while retaining the same
  safety checks as the main app.

## Requirements

- macOS 14 (Sonoma) or later on an Apple silicon (ARM64) Mac.
- [tart](https://github.com/openai/tart) 2.0.0 or later. Tart Manager
  does not bundle tart.

Install tart with Homebrew:

```sh
brew install cirruslabs/cli/tart
```

## Install

Download the DMG from the [latest GitHub release](../../releases/latest),
open it, and drag **Tart Manager** to **Applications**. The app is distributed
separately from tart, so install the requirement above first.

> **Unsigned release:** Tart Manager is not signed with an Apple Developer ID
> or notarized. macOS may warn that it cannot verify the developer. To open
> it, Control-click the app, choose **Open**, then confirm **Open** again.

## Get started

1. Open Tart Manager from Applications.
2. Choose the folder that contains your tart VM storage. The default is
   `~/.tart`.
3. Select a VM in the inventory and choose **Run**, or create one from an OCI
   image or IPSW restore image.

If the storage volume is unavailable, Tart Manager shows the cause and the
affected path, and lets you retry or choose another folder without restarting.
Tart Manager also checks storage again every 30 seconds and when you switch
back to the app, so the VM list comes back after you mount the volume.

## Documentation

- [Development guide](Docs/DEVELOPMENT.md) — build, test, and contribute.
- [Deployment guide](Docs/DEPLOYMENT.md) — package, sign, configure, and
  operate the app.
- [Changelog](CHANGELOG.md) — release history and unreleased changes.
- [License](LICENSE) — MIT License.

## Acknowledgments

Huge thanks to the creators and contributors of
[Tart](https://github.com/openai/tart), the virtualization toolset that makes
Tart Manager possible. Tart builds on Apple's Virtualization.framework to run
macOS and Linux VMs on Apple silicon.
